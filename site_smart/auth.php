<?php
declare(strict_types=1);

/**
 * Smart Student AI — account API.
 *
 *   GET  /auth/ping
 *   POST /auth/register   {name,email,password}
 *   POST /auth/verify     {email,code}
 *   POST /auth/resend     {email,purpose?}
 *   POST /auth/login      {email,password}
 *   POST /auth/forgot     {email}
 *   POST /auth/reset      {email,code,password}
 *   POST /auth/logout     (Bearer)
 *   GET  /auth/me         (Bearer)
 *   POST /auth/progress   (Bearer) {xp_delta,revision_delta,dictation_delta,best_score,source}
 *   POST /auth/sync       (Bearer) {xp,revision_count,dictation_count,best_score}
 *   GET  /auth/leaderboard
 *   GET  /auth/achievements (Bearer)
 */

error_reporting(E_ALL);
ini_set('display_errors', '0');
ini_set('log_errors', '1');

@set_time_limit(60);

$CONFIG = require __DIR__ . '/config.php';
require_once __DIR__ . '/db.php';

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, X-Router-Token');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Max-Age: 86400');
header('X-Content-Type-Options: nosniff');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

/* ------------------------------------------------------------------ */
/* Helpers                                                             */
/* ------------------------------------------------------------------ */

function a_json(array $data, int $code = 200): void
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function a_error(string $message, int $code = 400, string $type = 'invalid_request_error'): void
{
    a_json(['ok' => false, 'error' => ['message' => $message, 'type' => $type, 'code' => $code]], $code);
}

function a_body(): array
{
    $raw = file_get_contents('php://input');
    if (is_string($raw) && $raw !== '') {
        $data = json_decode($raw, true);
        if (is_array($data)) {
            return $data;
        }
    }
    return is_array($_POST) ? $_POST : [];
}

function a_str(array $src, string $key, string $default = ''): string
{
    $v = $src[$key] ?? $default;
    return is_scalar($v) ? trim((string) $v) : $default;
}

function a_int(array $src, string $key, int $default = 0): int
{
    $v = $src[$key] ?? $default;
    return is_numeric($v) ? (int) $v : $default;
}

function a_bearer(): string
{
    $header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if ($header === '' && function_exists('getallheaders')) {
        foreach (getallheaders() as $k => $v) {
            if (strcasecmp($k, 'Authorization') === 0) {
                $header = (string) $v;
                break;
            }
        }
    }
    if (preg_match('/Bearer\s+(.+)/i', (string) $header, $m)) {
        return trim($m[1]);
    }
    return '';
}

function a_conn(): PDO
{
    $pdo = ss_db();
    if (!$pdo) {
        a_error('The account database is not available right now.', 503, 'service_unavailable');
    }
    ss_db_init($pdo);
    return $pdo;
}

/** Resolves the authenticated user row, or terminates with 401. */
function a_require_user(PDO $pdo): array
{
    $token = a_bearer();
    if ($token === '') {
        a_error('Missing authentication token.', 401, 'authentication_error');
    }
    $stmt = $pdo->prepare(
        'SELECT u.*, s.expires_at FROM sessions s JOIN users u ON u.id = s.user_id
         WHERE s.token_hash = ? LIMIT 1'
    );
    $stmt->execute([hash('sha256', $token)]);
    $row = $stmt->fetch();
    if (!$row) {
        a_error('Session expired. Please sign in again.', 401, 'authentication_error');
    }
    if (strtotime((string) $row['expires_at']) < time()) {
        $pdo->prepare('DELETE FROM sessions WHERE token_hash = ?')->execute([hash('sha256', $token)]);
        a_error('Session expired. Please sign in again.', 401, 'authentication_error');
    }
    $pdo->prepare('UPDATE sessions SET last_seen = ? WHERE token_hash = ?')
        ->execute([gmdate('Y-m-d H:i:s'), hash('sha256', $token)]);
    return $row;
}

function a_create_session(PDO $pdo, int $userId): string
{
    $days = (int) ($GLOBALS['CONFIG']['auth']['session_days'] ?? 60);
    $token = bin2hex(random_bytes(32));
    $now = gmdate('Y-m-d H:i:s');
    $stmt = $pdo->prepare(
        'INSERT INTO sessions (token_hash, user_id, created_at, expires_at, last_seen)
         VALUES (?, ?, ?, ?, ?)'
    );
    $stmt->execute([hash('sha256', $token), $userId, $now, gmdate('Y-m-d H:i:s', time() + $days * 86400), $now]);
    return $token;
}

/* ------------------------------------------------------------------ */
/* OTP                                                                 */
/* ------------------------------------------------------------------ */

function a_gen_code(int $length): string
{
    $code = '';
    for ($i = 0; $i < $length; $i++) {
        $code .= (string) random_int(0, 9);
    }
    return $code;
}

function a_otp_rate_limited(PDO $pdo, string $email): bool
{
    $max = (int) ($GLOBALS['CONFIG']['mail']['max_per_hour'] ?? 5);
    $stmt = $pdo->prepare('SELECT COUNT(*) FROM otps WHERE email = ? AND created_at > ?');
    $stmt->execute([$email, gmdate('Y-m-d H:i:s', time() - 3600)]);
    return ((int) $stmt->fetchColumn()) >= $max;
}

function a_issue_otp(PDO $pdo, string $email, string $purpose): string
{
    // verify = create account, reset = forgot password, login = sign-in second factor
    $purpose = in_array($purpose, ['reset', 'login'], true) ? $purpose : 'verify';
    $length = (int) ($GLOBALS['CONFIG']['mail']['otp_length'] ?? 6);
    $ttl = (int) ($GLOBALS['CONFIG']['mail']['otp_ttl'] ?? 600);
    $code = a_gen_code($length);

    // Only the newest code may be used.
    $pdo->prepare('UPDATE otps SET consumed = 1 WHERE email = ? AND purpose = ? AND consumed = 0')
        ->execute([$email, $purpose]);

    $stmt = $pdo->prepare(
        'INSERT INTO otps (email, code_hash, purpose, attempts, consumed, expires_at, created_at)
         VALUES (?, ?, ?, 0, 0, ?, ?)'
    );
    $stmt->execute([
        $email,
        hash('sha256', $code),
        $purpose,
        gmdate('Y-m-d H:i:s', time() + $ttl),
        gmdate('Y-m-d H:i:s'),
    ]);

    return $code;
}

/**
 * Validates an OTP for the given purpose and marks it consumed.
 * Sends the matching error response (and exits) when the code is not valid.
 */
function a_consume_otp(PDO $pdo, string $email, string $purpose, string $code): array
{
    $stmt = $pdo->prepare(
        'SELECT * FROM otps WHERE email = ? AND purpose = ? AND consumed = 0 ORDER BY id DESC LIMIT 1'
    );
    $stmt->execute([$email, $purpose]);
    $otp = $stmt->fetch();
    if (!$otp) a_error('No active code. Please request a new one.', 400, 'no_otp');
    if (strtotime((string) $otp['expires_at']) < time()) a_error('This code has expired. Request a new one.', 400, 'otp_expired');
    if ((int) $otp['attempts'] >= 8) a_error('Too many attempts. Request a new code.', 429, 'too_many_attempts');
    if (!hash_equals((string) $otp['code_hash'], hash('sha256', $code))) {
        $pdo->prepare('UPDATE otps SET attempts = attempts + 1 WHERE id = ?')->execute([$otp['id']]);
        a_error('Incorrect code. Please try again.', 400, 'bad_code');
    }
    $pdo->prepare('UPDATE otps SET consumed = 1 WHERE id = ?')->execute([$otp['id']]);
    return $otp;
}

/** Sends the OTP email. Returns true when the mail transport accepted it. */
function a_send_otp(string $email, string $code, string $purpose): bool
{
    $mail = $GLOBALS['CONFIG']['mail'] ?? [];
    $fromEmail = (string) ($mail['from_email'] ?? 'no-reply@smart.chrif.net');
    $fromName  = (string) ($mail['from_name'] ?? 'Smart Student AI');
    $isReset   = $purpose === 'reset';
    $isLogin   = $purpose === 'login';

    if ($isReset) {
        $subject = 'Reset your Smart Student AI password';
        $lead = 'Use the code below to reset your password.';
    } elseif ($isLogin) {
        $subject = 'Your Smart Student AI sign-in code';
        $lead = 'Use the code below to finish signing in to your account.';
    } else {
        $subject = 'Confirm your Smart Student AI account';
        $lead = 'Welcome to Smart Student AI! Use the code below to confirm your email address.';
    }
    $ttlMin = (int) round(((int) ($mail['otp_ttl'] ?? 600)) / 60);

    $text = "Smart Student AI\n\n{$lead}\n\nYour code: {$code}\n\n"
        . "This code expires in {$ttlMin} minutes. If you did not request it, you can ignore this email.\n";

    $safeCode = htmlspecialchars($code, ENT_QUOTES, 'UTF-8');
    $html = '<!doctype html><html><body style="margin:0;background:#eef2f8;padding:32px 0;'
        . 'font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1b2430">'
        . '<div style="max-width:520px;margin:0 auto;background:#ffffff;border-radius:20px;overflow:hidden;'
        . 'box-shadow:0 12px 40px rgba(15,40,80,.12)">'
        . '<div style="background:linear-gradient(135deg,#0f4c81,#163b5a);padding:28px 32px;color:#e8f3ff">'
        . '<div style="font-size:22px;font-weight:800;letter-spacing:-.4px">Smart Student AI</div>'
        . '<div style="opacity:.85;font-size:13px;margin-top:4px">Learn smarter, every day</div></div>'
        . '<div style="padding:32px">'
        . '<p style="font-size:15px;line-height:1.6;margin:0 0 20px">' . htmlspecialchars($lead, ENT_QUOTES) . '</p>'
        . '<div style="text-align:center;margin:26px 0">'
        . '<span style="display:inline-block;font-size:34px;font-weight:800;letter-spacing:10px;'
        . 'color:#0f4c81;background:#eef4fc;border-radius:14px;padding:16px 22px 16px 30px">' . $safeCode . '</span>'
        . '</div>'
        . '<p style="font-size:13px;color:#64748b;line-height:1.6;margin:0">This code expires in '
        . $ttlMin . ' minutes. If you did not request it, you can safely ignore this email.</p>'
        . '</div>'
        . '<div style="padding:18px 32px;background:#f8fafc;color:#94a3b8;font-size:12px;'
        . 'border-top:1px solid #eef2f7">Sent by ' . htmlspecialchars($fromName, ENT_QUOTES)
        . ' &middot; ' . htmlspecialchars($fromEmail, ENT_QUOTES) . '</div>'
        . '</div></body></html>';

    $boundary = '=_ss_' . bin2hex(random_bytes(8));
    $headers = [
        'Date: ' . date('r'),
        'Message-ID: <' . bin2hex(random_bytes(12)) . '@smart.chrif.net>',
        'MIME-Version: 1.0',
        'From: ' . $fromName . ' <' . $fromEmail . '>',
        'To: <' . $email . '>',
        'Subject: ' . $subject,
        'Reply-To: ' . $fromEmail,
        'X-Mailer: SmartStudentAI',
        'Content-Type: multipart/alternative; boundary="' . $boundary . '"',
    ];

    $body = "--{$boundary}\r\n"
        . "Content-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n"
        . $text . "\r\n"
        . "--{$boundary}\r\n"
        . "Content-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n"
        . $html . "\r\n"
        . "--{$boundary}--";

    return a_deliver_mail($fromEmail, $email, $subject, $headers, $body);
}

/**
 * Delivers a message. Prefers the authenticated SMTP relay (reliable + DKIM
 * signed by Hostinger) and falls back to the local PHP mail() transport.
 */
function a_deliver_mail(string $fromEmail, string $to, string $subject, array $headers, string $body): bool
{
    $smtp = $GLOBALS['CONFIG']['mail']['smtp'] ?? [];
    if (!empty($smtp['user']) && !empty($smtp['pass'])) {
        if (a_smtp_send($smtp, $fromEmail, $to, $headers, $body)) {
            return true;
        }
        error_log('SmartStudent mail: SMTP relay failed (' . ($GLOBALS['SS_SMTP_ERROR'] ?? 'unknown') . '); trying mail()');
    }

    // mail() only wants headers it should add itself omitted.
    $mailHeaders = [];
    foreach ($headers as $h) {
        if (preg_match('/^(date|message-id|to|subject):/i', $h)) {
            continue;
        }
        $mailHeaders[] = $h;
    }
    $ok = (bool) @mail($to, $subject, $body, implode("\r\n", $mailHeaders), '-f' . $fromEmail);
    if (!$ok) {
        error_log('SmartStudent mail: delivery to ' . $to . ' failed on every transport');
    }
    return $ok;
}

/** Minimal SMTP client (SSL or STARTTLS) using only core PHP. */
function a_smtp_send(array $cfg, string $fromEmail, string $to, array $headers, string $body): bool
{
    $host = (string) ($cfg['host'] ?? 'smtp.hostinger.com');
    $port = (int) ($cfg['port'] ?? 465);
    $user = (string) $cfg['user'];
    $pass = (string) $cfg['pass'];

    $fail = static function (string $why): bool {
        $GLOBALS['SS_SMTP_ERROR'] = $why;
        return false;
    };

    $prefix = $port === 465 ? 'ssl://' : 'tcp://';
    $ctx = stream_context_create(['ssl' => [
        'verify_peer' => true, 'verify_peer_name' => true, 'SNI_enabled' => true,
    ]]);
    $fp = @stream_socket_client($prefix . $host . ':' . $port, $errno, $errstr, 20, STREAM_CLIENT_CONNECT, $ctx);
    if (!$fp) {
        return $fail("connect failed to {$prefix}{$host}:{$port} ({$errno} {$errstr})");
    }
    stream_set_timeout($fp, 20);

    $read = static function () use ($fp): string {
        $data = '';
        while (($line = fgets($fp, 2048)) !== false) {
            $data .= $line;
            if (strlen($line) < 4 || $line[3] !== '-') {
                break;
            }
        }
        return $data;
    };
    $send = static function (string $cmd) use ($fp, $read): string {
        fwrite($fp, $cmd . "\r\n");
        return $read();
    };

    $read(); // server greeting
    $send('EHLO smart.chrif.net');

    if ($port !== 465) {
        $send('STARTTLS');
        if (!@stream_socket_enable_crypto($fp, true, STREAM_CRYPTO_METHOD_TLS_CLIENT)) {
            fclose($fp);
            return $fail('STARTTLS failed');
        }
        $send('EHLO smart.chrif.net');
    }

    $send('AUTH LOGIN');
    $send(base64_encode($user));
    $auth = $send(base64_encode($pass));
    if (strpos($auth, '235') === false) {
        fclose($fp);
        return $fail('auth rejected: ' . trim($auth));
    }

    $r = $send('MAIL FROM:<' . $fromEmail . '>');
    if (strpos($r, '250') === false) { fclose($fp); return $fail('MAIL FROM rejected: ' . trim($r)); }
    $r = $send('RCPT TO:<' . $to . '>');
    if (strpos($r, '250') === false && strpos($r, '251') === false) { fclose($fp); return $fail('RCPT TO rejected: ' . trim($r)); }
    $send('DATA');

    $data = implode("\r\n", $headers) . "\r\n\r\n" . $body;
    $data = preg_replace('/^\./m', '..', $data);
    fwrite($fp, $data . "\r\n.\r\n");
    $done = $read();
    $send('QUIT');
    fclose($fp);

    if (strpos($done, '250') === false) {
        return $fail('DATA rejected: ' . trim($done));
    }
    return true;
}

/* ------------------------------------------------------------------ */
/* Progress / achievements                                             */
/* ------------------------------------------------------------------ */

function a_progress_row(PDO $pdo, int $userId): array
{
    $stmt = $pdo->prepare('SELECT * FROM progress WHERE user_id = ?');
    $stmt->execute([$userId]);
    $row = $stmt->fetch();
    if (!$row) {
        $now = gmdate('Y-m-d H:i:s');
        $pdo->prepare(
            'INSERT INTO progress (user_id, xp, level, revision_count, dictation_count, best_score,
                streak, longest_streak, last_active, daily_goal, today_xp, updated_at)
             VALUES (?, 0, 1, 0, 0, 0, 0, 0, NULL, 50, 0, ?)'
        )->execute([$userId, $now]);
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
    }
    return $row ?: [];
}

/** Applies XP / activity deltas, maintains streaks, returns the fresh row. */
function a_apply_progress(PDO $pdo, int $userId, array $d): array
{
    $row = a_progress_row($pdo, $userId);
    $today = gmdate('Y-m-d');
    $yesterday = gmdate('Y-m-d', time() - 86400);

    $xpDelta        = max(-100000, min(100000, (int) ($d['xp_delta'] ?? 0)));
    $revisionDelta  = max(0, min(1000, (int) ($d['revision_delta'] ?? 0)));
    $dictationDelta = max(0, min(1000, (int) ($d['dictation_delta'] ?? 0)));
    $bestScore      = max((int) $row['best_score'], min(100000, (int) ($d['best_score'] ?? 0)));
    $source         = substr(preg_replace('/[^a-z_]/', '', strtolower((string) ($d['source'] ?? 'app'))), 0, 30);

    $lastActive = $row['last_active'];
    $streak = (int) $row['streak'];
    $longest = (int) $row['longest_streak'];
    $todayXp = (int) $row['today_xp'];

    if ($lastActive !== $today) {
        $todayXp = 0; // new day
        if ($lastActive === $yesterday) {
            $streak = max(1, $streak + 1);
        } else {
            $streak = 1;
        }
    } elseif ($streak < 1) {
        $streak = 1;
    }

    $xp = max(0, (int) $row['xp'] + $xpDelta);
    $todayXp = max(0, $todayXp + max(0, $xpDelta));
    $longest = max($longest, $streak);
    $level = ss_level_for_xp($xp);

    if ($xpDelta !== 0) {
        $pdo->prepare('INSERT INTO xp_events (user_id, xp, source, created_at) VALUES (?, ?, ?, ?)')
            ->execute([$userId, $xpDelta, $source, gmdate('Y-m-d H:i:s')]);
    }

    $pdo->prepare(
        'UPDATE progress SET xp = ?, level = ?, revision_count = ?, dictation_count = ?, best_score = ?,
            streak = ?, longest_streak = ?, last_active = ?, today_xp = ?, updated_at = ?
         WHERE user_id = ?'
    )->execute([
        $xp, $level,
        (int) $row['revision_count'] + $revisionDelta,
        (int) $row['dictation_count'] + $dictationDelta,
        $bestScore, $streak, $longest, $today, $todayXp, gmdate('Y-m-d H:i:s'), $userId,
    ]);

    return a_progress_row($pdo, $userId);
}

function a_achievement_defs(): array
{
    return [
        ['code' => 'first_steps',  'title' => 'First Steps',     'desc' => 'Earn your first XP',            'icon' => 'spark',      'test' => fn(array $p) => $p['xp'] >= 1],
        ['code' => 'level_5',      'title' => 'Rising Star',     'desc' => 'Reach level 5',                 'icon' => 'star',       'test' => fn(array $p) => $p['level'] >= 5],
        ['code' => 'level_10',     'title' => 'Scholar',         'desc' => 'Reach level 10',                'icon' => 'school',     'test' => fn(array $p) => $p['level'] >= 10],
        ['code' => 'level_25',     'title' => 'Mastermind',      'desc' => 'Reach level 25',                'icon' => 'brain',      'test' => fn(array $p) => $p['level'] >= 25],
        ['code' => 'xp_500',       'title' => 'XP Hunter',       'desc' => 'Collect 500 XP',                'icon' => 'bolt',       'test' => fn(array $p) => $p['xp'] >= 500],
        ['code' => 'xp_2000',      'title' => 'XP Legend',       'desc' => 'Collect 2,000 XP',              'icon' => 'local_fire', 'test' => fn(array $p) => $p['xp'] >= 2000],
        ['code' => 'streak_3',     'title' => 'Warming Up',      'desc' => '3-day learning streak',         'icon' => 'sunny',      'test' => fn(array $p) => $p['longest_streak'] >= 3],
        ['code' => 'streak_7',     'title' => 'On Fire',         'desc' => '7-day learning streak',         'icon' => 'flame',      'test' => fn(array $p) => $p['longest_streak'] >= 7],
        ['code' => 'streak_30',    'title' => 'Unstoppable',     'desc' => '30-day learning streak',        'icon' => 'crown',      'test' => fn(array $p) => $p['longest_streak'] >= 30],
        ['code' => 'revision_25',  'title' => 'Quiz Explorer',   'desc' => 'Answer 25 revision questions',  'icon' => 'quiz',       'test' => fn(array $p) => $p['revision_count'] >= 25],
        ['code' => 'dictation_10', 'title' => 'Golden Ear',      'desc' => 'Finish 10 dictation sessions',  'icon' => 'mic',        'test' => fn(array $p) => $p['dictation_count'] >= 10],
    ];
}

/** Returns [all defs with unlocked flag, list of newly unlocked codes]. */
function a_sync_achievements(PDO $pdo, int $userId, array $progress): array
{
    $stmt = $pdo->prepare('SELECT code FROM achievements WHERE user_id = ?');
    $stmt->execute([$userId]);
    $have = array_column($stmt->fetchAll(), 'code');

    $new = [];
    foreach (a_achievement_defs() as $def) {
        if (in_array($def['code'], $have, true)) {
            continue;
        }
        if (($def['test'])($progress)) {
            $pdo->prepare('INSERT IGNORE INTO achievements (user_id, code, unlocked_at) VALUES (?, ?, ?)')
                ->execute([$userId, $def['code'], gmdate('Y-m-d H:i:s')]);
            $have[] = $def['code'];
            $new[] = $def['code'];
        }
    }
    return [$have, $new];
}

function a_public_progress(array $p): array
{
    $xp = (int) $p['xp'];
    $intoLevel = $xp % SS_XP_PER_LEVEL;
    return [
        'xp'              => $xp,
        'level'           => (int) $p['level'],
        'xp_into_level'   => $intoLevel,
        'xp_per_level'    => SS_XP_PER_LEVEL,
        'level_progress'  => $intoLevel / SS_XP_PER_LEVEL,
        'revision_count'  => (int) $p['revision_count'],
        'dictation_count' => (int) $p['dictation_count'],
        'best_score'      => (int) $p['best_score'],
        'streak'          => (int) $p['streak'],
        'longest_streak'  => (int) $p['longest_streak'],
        'today_xp'        => (int) $p['today_xp'],
        'daily_goal'      => (int) $p['daily_goal'],
        'last_active'     => $p['last_active'],
        'updated_at'      => $p['updated_at'],
    ];
}

function a_public_user(array $u): array
{
    return [
        'id'         => (int) $u['id'],
        'name'       => (string) $u['name'],
        'email'      => (string) $u['email'],
        'verified'   => (bool) $u['verified'],
        'created_at' => (string) $u['created_at'],
    ];
}

/* ------------------------------------------------------------------ */
/* Dispatch                                                            */
/* ------------------------------------------------------------------ */

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
$action = strtolower(trim((string) ($_GET['action'] ?? '')));
if ($action === '' && preg_match('#/auth/([a-z_]+)#', (string) parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH), $m)) {
    $action = $m[1];
}
$in = a_body();

if ($action === 'ping' || $action === '') {
    $pdo = ss_db();
    $dbOk = false;
    if ($pdo) {
        try { ss_db_init($pdo); $dbOk = true; } catch (Throwable $e) { $dbOk = false; }
    }
    a_json(['ok' => true, 'service' => 'smart-student-ai-auth', 'database' => $dbOk, 'time' => gmdate('c')]);
}

if ($method !== 'POST' && $action !== 'me' && $action !== 'leaderboard' && $action !== 'achievements') {
    a_error('Method not allowed.', 405, 'method_not_allowed');
}

switch ($action) {
    case 'register': {
        $pdo = a_conn();
        $name = a_str($in, 'name');
        $email = strtolower(a_str($in, 'email'));
        $password = (string) ($in['password'] ?? '');

        if ($name === '' || mb_strlen($name) < 2) a_error('Please enter your name.');
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) a_error('Please enter a valid email address.');
        if (strlen($password) < 8) a_error('Password must be at least 8 characters.');

        $stmt = $pdo->prepare('SELECT * FROM users WHERE email = ? LIMIT 1');
        $stmt->execute([$email]);
        $existing = $stmt->fetch();

        if ($existing && (int) $existing['verified'] === 1) {
            a_error('An account with this email already exists. Try signing in.', 409, 'email_taken');
        }

        if ($existing) {
            $pdo->prepare('UPDATE users SET name = ?, password_hash = ?, updated_at = ? WHERE id = ?')
                ->execute([$name, password_hash($password, PASSWORD_DEFAULT), gmdate('Y-m-d H:i:s'), $existing['id']]);
            $userId = (int) $existing['id'];
        } else {
            $pdo->prepare(
                'INSERT INTO users (name, email, password_hash, verified, created_at, updated_at)
                 VALUES (?, ?, ?, 0, ?, ?)'
            )->execute([$name, $email, password_hash($password, PASSWORD_DEFAULT), gmdate('Y-m-d H:i:s'), gmdate('Y-m-d H:i:s')]);
            $userId = (int) $pdo->lastInsertId();
        }

        a_progress_row($pdo, $userId);

        if (a_otp_rate_limited($pdo, $email)) {
            a_error('Too many verification codes requested. Please wait a few minutes.', 429, 'rate_limited');
        }
        $code = a_issue_otp($pdo, $email, 'verify');
        $sent = a_send_otp($email, $code, 'verify');

        a_json([
            'ok' => true,
            'requires_verification' => true,
            'email' => $email,
            'mail_sent' => $sent,
            'message' => $sent
                ? 'We emailed a 6-digit code to ' . $email . '.'
                : 'Account created, but the email could not be sent. Please tap resend.',
        ]);
    }

    case 'verify': {
        $pdo = a_conn();
        $email = strtolower(a_str($in, 'email'));
        $code = a_str($in, 'code');
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || $code === '') a_error('Email and code are required.');

        $stmt = $pdo->prepare(
            'SELECT * FROM otps WHERE email = ? AND purpose = ? AND consumed = 0 ORDER BY id DESC LIMIT 1'
        );
        $stmt->execute([$email, 'verify']);
        $otp = $stmt->fetch();
        if (!$otp) a_error('No active code. Please request a new one.', 400, 'no_otp');
        if (strtotime((string) $otp['expires_at']) < time()) a_error('This code has expired. Request a new one.', 400, 'otp_expired');
        if ((int) $otp['attempts'] >= 8) a_error('Too many attempts. Request a new code.', 429, 'too_many_attempts');
        if (!hash_equals((string) $otp['code_hash'], hash('sha256', $code))) {
            $pdo->prepare('UPDATE otps SET attempts = attempts + 1 WHERE id = ?')->execute([$otp['id']]);
            a_error('Incorrect code. Please try again.', 400, 'bad_code');
        }

        $pdo->prepare('UPDATE otps SET consumed = 1 WHERE id = ?')->execute([$otp['id']]);
        $pdo->prepare('UPDATE users SET verified = 1, updated_at = ? WHERE email = ?')->execute([gmdate('Y-m-d H:i:s'), $email]);
        $stmt = $pdo->prepare('SELECT * FROM users WHERE email = ? LIMIT 1');
        $stmt->execute([$email]);
        $user = $stmt->fetch();
        if (!$user) a_error('Account not found.', 404, 'not_found');

        $token = a_create_session($pdo, (int) $user['id']);
        $progress = a_progress_row($pdo, (int) $user['id']);
        [$ach] = a_sync_achievements($pdo, (int) $user['id'], $progress);

        a_json([
            'ok' => true, 'token' => $token,
            'user' => a_public_user($user),
            'progress' => a_public_progress($progress),
            'achievements' => $ach,
        ]);
    }

    case 'resend': {
        $pdo = a_conn();
        $email = strtolower(a_str($in, 'email'));
        $requested = a_str($in, 'purpose', 'verify');
        $purpose = in_array($requested, ['reset', 'login'], true) ? $requested : 'verify';
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) a_error('Please enter a valid email address.');

        $stmt = $pdo->prepare('SELECT id, verified FROM users WHERE email = ? LIMIT 1');
        $stmt->execute([$email]);
        $user = $stmt->fetch();
        if (!$user) a_error('No account found for that email.', 404, 'not_found');
        if ($purpose === 'verify' && (int) $user['verified'] === 1) {
            a_json(['ok' => true, 'already_verified' => true, 'message' => 'This email is already confirmed. You can sign in.']);
        }
        if ($purpose === 'login' && (int) $user['verified'] !== 1) {
            a_error('Please confirm your email first.', 403, 'unverified');
        }
        if (a_otp_rate_limited($pdo, $email)) a_error('Too many codes requested. Please wait a few minutes.', 429, 'rate_limited');

        $code = a_issue_otp($pdo, $email, $purpose);
        $sent = a_send_otp($email, $code, $purpose);
        a_json(['ok' => true, 'mail_sent' => $sent, 'message' => $sent ? 'A new code is on its way.' : 'Could not send the email. Try again shortly.']);
    }

    case 'login': {
        $pdo = a_conn();
        $email = strtolower(a_str($in, 'email'));
        $password = (string) ($in['password'] ?? '');
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || $password === '') a_error('Email and password are required.');

        $stmt = $pdo->prepare('SELECT * FROM users WHERE email = ? LIMIT 1');
        $stmt->execute([$email]);
        $user = $stmt->fetch();
        if (!$user || !password_verify($password, (string) $user['password_hash'])) {
            a_error('Invalid email or password.', 401, 'bad_credentials');
        }
        if ((int) $user['verified'] !== 1) {
            a_json([
                'ok' => false,
                'requires_verification' => true,
                'email' => $email,
                'error' => ['message' => 'Please confirm your email first. We can resend the code.', 'type' => 'unverified', 'code' => 403],
            ], 403);
        }

        // Password alone is never enough: every sign-in needs an emailed code.
        if (a_otp_rate_limited($pdo, $email)) {
            a_error('Too many sign-in codes requested. Please wait a few minutes.', 429, 'rate_limited');
        }
        $code = a_issue_otp($pdo, $email, 'login');
        $sent = a_send_otp($email, $code, 'login');

        a_json([
            'ok' => true,
            'requires_otp' => true,
            'email' => $email,
            'mail_sent' => $sent,
            'message' => $sent
                ? 'We emailed a sign-in code to ' . $email . '.'
                : 'We could not send the email. Please tap resend.',
        ]);
    }

    case 'login_verify': {
        $pdo = a_conn();
        $email = strtolower(a_str($in, 'email'));
        $code = a_str($in, 'code');
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || $code === '') a_error('Email and code are required.');

        a_consume_otp($pdo, $email, 'login', $code);

        $stmt = $pdo->prepare('SELECT * FROM users WHERE email = ? LIMIT 1');
        $stmt->execute([$email]);
        $user = $stmt->fetch();
        if (!$user) a_error('Account not found.', 404, 'not_found');

        $token = a_create_session($pdo, (int) $user['id']);
        $progress = a_progress_row($pdo, (int) $user['id']);
        [$ach] = a_sync_achievements($pdo, (int) $user['id'], $progress);
        a_json([
            'ok' => true, 'token' => $token,
            'user' => a_public_user($user),
            'progress' => a_public_progress($progress),
            'achievements' => $ach,
        ]);
    }

    case 'forgot': {
        $pdo = a_conn();
        $email = strtolower(a_str($in, 'email'));
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) a_error('Please enter a valid email address.');

        $stmt = $pdo->prepare('SELECT id FROM users WHERE email = ? LIMIT 1');
        $stmt->execute([$email]);
        $user = $stmt->fetch();

        // Always answer the same way to avoid leaking which emails exist.
        if ($user && !a_otp_rate_limited($pdo, $email)) {
            $code = a_issue_otp($pdo, $email, 'reset');
            a_send_otp($email, $code, 'reset');
        }
        a_json(['ok' => true, 'message' => 'If that email exists, a reset code has been sent.']);
    }

    case 'reset': {
        $pdo = a_conn();
        $email = strtolower(a_str($in, 'email'));
        $code = a_str($in, 'code');
        $password = (string) ($in['password'] ?? '');
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || $code === '') a_error('Email and code are required.');
        if (strlen($password) < 8) a_error('Password must be at least 8 characters.');

        $stmt = $pdo->prepare('SELECT * FROM otps WHERE email = ? AND purpose = ? AND consumed = 0 ORDER BY id DESC LIMIT 1');
        $stmt->execute([$email, 'reset']);
        $otp = $stmt->fetch();
        if (!$otp) a_error('No active reset code. Please request a new one.', 400, 'no_otp');
        if (strtotime((string) $otp['expires_at']) < time()) a_error('This code has expired. Request a new one.', 400, 'otp_expired');
        if ((int) $otp['attempts'] >= 8) a_error('Too many attempts. Request a new code.', 429, 'too_many_attempts');
        if (!hash_equals((string) $otp['code_hash'], hash('sha256', $code))) {
            $pdo->prepare('UPDATE otps SET attempts = attempts + 1 WHERE id = ?')->execute([$otp['id']]);
            a_error('Incorrect code. Please try again.', 400, 'bad_code');
        }

        $pdo->prepare('UPDATE otps SET consumed = 1 WHERE id = ?')->execute([$otp['id']]);
        $pdo->prepare('UPDATE users SET password_hash = ?, verified = 1, updated_at = ? WHERE email = ?')
            ->execute([password_hash($password, PASSWORD_DEFAULT), gmdate('Y-m-d H:i:s'), $email]);
        // Invalidate old sessions for safety.
        $stmt = $pdo->prepare('SELECT id FROM users WHERE email = ? LIMIT 1');
        $stmt->execute([$email]);
        if ($u = $stmt->fetch()) {
            $pdo->prepare('DELETE FROM sessions WHERE user_id = ?')->execute([$u['id']]);
        }
        a_json(['ok' => true, 'message' => 'Password updated. You can sign in now.']);
    }

    case 'logout': {
        $pdo = a_conn();
        $token = a_bearer();
        if ($token !== '') {
            $pdo->prepare('DELETE FROM sessions WHERE token_hash = ?')->execute([hash('sha256', $token)]);
        }
        a_json(['ok' => true]);
    }

    case 'me': {
        $pdo = a_conn();
        $user = a_require_user($pdo);
        $progress = a_progress_row($pdo, (int) $user['id']);
        [$ach] = a_sync_achievements($pdo, (int) $user['id'], $progress);
        a_json([
            'ok' => true,
            'user' => a_public_user($user),
            'progress' => a_public_progress($progress),
            'achievements' => $ach,
        ]);
    }

    case 'progress': {
        $pdo = a_conn();
        $user = a_require_user($pdo);
        $updated = a_apply_progress($pdo, (int) $user['id'], $in);
        [$ach, $new] = a_sync_achievements($pdo, (int) $user['id'], $updated);
        a_json([
            'ok' => true,
            'progress' => a_public_progress($updated),
            'achievements' => $ach,
            'new_achievements' => $new,
        ]);
    }

    case 'sync': {
        $pdo = a_conn();
        $user = a_require_user($pdo);
        $row = a_progress_row($pdo, (int) $user['id']);

        // Only seed from local when the cloud copy is still empty.
        if ((int) $row['xp'] === 0 && (int) $row['revision_count'] === 0 && (int) $row['dictation_count'] === 0) {
            $xp = max(0, min(1000000, a_int($in, 'xp')));
            $rev = max(0, min(100000, a_int($in, 'revision_count')));
            $dic = max(0, min(100000, a_int($in, 'dictation_count')));
            $best = max(0, min(100000, a_int($in, 'best_score')));
            $pdo->prepare(
                'UPDATE progress SET xp = ?, level = ?, revision_count = ?, dictation_count = ?, best_score = ?, updated_at = ? WHERE user_id = ?'
            )->execute([$xp, ss_level_for_xp($xp), $rev, $dic, $best, gmdate('Y-m-d H:i:s'), $user['id']]);
            $row = a_progress_row($pdo, (int) $user['id']);
        }
        [$ach, $new] = a_sync_achievements($pdo, (int) $user['id'], $row);
        a_json(['ok' => true, 'progress' => a_public_progress($row), 'achievements' => $ach, 'new_achievements' => $new]);
    }

    case 'leaderboard': {
        $pdo = a_conn();
        $limit = max(3, min(100, a_int($_GET, 'limit', 50)));
        $stmt = $pdo->prepare(
            'SELECT u.name, u.id, p.xp, p.level, p.streak, p.revision_count, p.dictation_count
             FROM progress p JOIN users u ON u.id = p.user_id
             WHERE u.verified = 1
             ORDER BY p.xp DESC, p.updated_at ASC LIMIT ' . $limit
        );
        $stmt->execute();
        $rows = $stmt->fetchAll();
        $out = [];
        $rank = 0;
        foreach ($rows as $r) {
            $rank++;
            $out[] = [
                'rank' => $rank,
                'name' => (string) $r['name'],
                'xp' => (int) $r['xp'],
                'level' => (int) $r['level'],
                'streak' => (int) $r['streak'],
                'revision_count' => (int) $r['revision_count'],
                'dictation_count' => (int) $r['dictation_count'],
            ];
        }
        $defs = [];
        foreach (a_achievement_defs() as $d) {
            $defs[] = ['code' => $d['code'], 'title' => $d['title'], 'desc' => $d['desc'], 'icon' => $d['icon']];
        }
        a_json(['ok' => true, 'leaderboard' => $out, 'achievement_defs' => $defs]);
    }

    case 'achievements': {
        $pdo = a_conn();
        $user = a_require_user($pdo);
        $progress = a_progress_row($pdo, (int) $user['id']);
        [$ach] = a_sync_achievements($pdo, (int) $user['id'], $progress);
        $defs = [];
        foreach (a_achievement_defs() as $d) {
            $defs[] = [
                'code' => $d['code'], 'title' => $d['title'], 'desc' => $d['desc'], 'icon' => $d['icon'],
                'unlocked' => in_array($d['code'], $ach, true),
            ];
        }
        a_json(['ok' => true, 'achievements' => $defs, 'unlocked' => $ach]);
    }

    default:
        a_error('Unknown auth action "' . $action . '".', 404, 'not_found');
}
