<?php
/**
 * Smart Student AI — Keyless OCR router
 *
 *   POST /ocr   { image_base64 | url, mime?, language? }  -> best text
 *   GET  /ocr?action=providers                            -> provider list
 *   GET  /ocr?action=ping                                 -> health
 *
 * The router fans out to several *free* OCR engines that need no account,
 * token or API key from the caller, scores every result and returns the
 * highest-quality text together with which engine won.
 *
 * Providers
 *   1. OCR.space "helloworld" demo key, engine 2 (neural, multilingual)
 *   2. OCR.space engine 1 (classic, sometimes better on clean scans)
 *   3. Local Tesseract CLI (only when the binary is installed on the host)
 *   4. Groq vision (server-side key from keys.php) — last-resort insurance
 *
 * Nothing in this file requires the app to hold a key.
 */

declare(strict_types=1);

error_reporting(E_ALL);
ini_set('display_errors', '0');
ini_set('log_errors', '1');

// Temporary diagnostics: append &diag=<token> to see the real error text.
if (($_GET['diag'] ?? '') === 'ss-ocr-diag-1177') {
    ini_set('display_errors', '1');
}

$CONFIG = require __DIR__ . '/config.php';

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Max-Age: 86400');
header('X-Content-Type-Options: nosniff');
header('Content-Type: application/json; charset=utf-8');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

@set_time_limit(90);
ignore_user_abort(true);

const OCR_MAX_BYTES      = 12 * 1024 * 1024; // 12 MB of base64 payload
const OCR_TOTAL_BUDGET   = 55.0;            // seconds across all providers
const OCR_GOOD_ENOUGH    = 420.0;           // score that ends the search early
const OCR_MAX_CHARS      = 200000;

/* ------------------------------------------------------------------ */
/* Helpers                                                            */
/* ------------------------------------------------------------------ */

function o_json(array $data, int $code = 200): void
{
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function o_error(string $message, int $code = 400, string $type = 'invalid_request_error'): void
{
    o_json(['ok' => false, 'error' => ['message' => $message, 'type' => $type]], $code);
}

function o_body(): array
{
    $raw = file_get_contents('php://input');
    if ($raw === false || trim($raw) === '') {
        return is_array($_POST) ? $_POST : [];
    }
    $decoded = json_decode($raw, true);
    if (is_array($decoded)) {
        return $decoded;
    }
    // Allow classic form posts too.
    parse_str($raw, $form);
    return is_array($form) ? $form : [];
}

function o_str(array $src, string $key, string $default = ''): string
{
    return isset($src[$key]) && is_scalar($src[$key]) ? trim((string) $src[$key]) : $default;
}

function o_runtime_dir(): string
{
    $dir = __DIR__ . '/runtime';
    if (!is_dir($dir)) {
        @mkdir($dir, 0755, true);
    }
    return $dir;
}

/** Simple per-IP hourly quota so the public endpoint cannot be abused. */
function o_rate_limited(string $bucket, int $limit, int $window = 3600): bool
{
    $ip = (string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown');
    $file = o_runtime_dir() . '/ocr_rate.json';
    $fh = @fopen($file, 'c+');
    if (!$fh) {
        return false; // never block when the filesystem is not writable
    }
    try {
        @flock($fh, LOCK_EX);
        $raw = stream_get_contents($fh);
        $data = json_decode((string) $raw, true);
        if (!is_array($data)) {
            $data = [];
        }
        $now = time();
        // Drop stale buckets.
        foreach ($data as $k => $v) {
            if (!is_array($v) || ($now - (int) ($v['start'] ?? 0)) > $window) {
                unset($data[$k]);
            }
        }
        $key = $bucket . ':' . $ip;
        if (!isset($data[$key]) || ($now - (int) $data[$key]['start']) > $window) {
            $data[$key] = ['start' => $now, 'count' => 0];
        }
        $data[$key]['count'] = (int) $data[$key]['count'] + 1;
        $count = (int) $data[$key]['count'];
        @ftruncate($fh, 0);
        @rewind($fh);
        @fwrite($fh, json_encode($data));
        @fflush($fh);
        return $count > $limit;
    } finally {
        @flock($fh, LOCK_UN);
        @fclose($fh);
    }
}

/** Normalises OCR output: unifies newlines, trims trailing spaces, collapses blanks. */
function o_clean(string $text): string
{
    $text = str_replace(["\r\n", "\r", "\xC2\xA0"], ["\n", "\n", ' '], $text);
    $text = preg_replace('/[ \t]+/u', ' ', $text) ?? $text;
    $text = preg_replace('/\n{3,}/u', "\n\n", $text) ?? $text;
    $text = trim($text);
    if (mb_strlen($text) > OCR_MAX_CHARS) {
        $text = mb_substr($text, 0, OCR_MAX_CHARS);
    }
    return $text;
}

/**
 * Quality score for an OCR result. Rewards real content (letters, words),
 * penalises symbol soup and replacement glyphs. Higher is better.
 */
function o_score(string $text, string $lang): float
{
    $text = trim($text);
    if ($text === '') {
        return 0.0;
    }
    $len = mb_strlen($text);
    $letters = (int) preg_match_all('/[\p{L}\p{N}]/u', $text);
    $words = count(preg_split('/\s+/u', $text, -1, PREG_SPLIT_NO_EMPTY) ?: []);
    $letterRatio = $letters / max(1, $len);

    $score = min($len, 6000) * 0.35
        + min($words, 1200) * 0.9
        + $letterRatio * 260;

    if ($lang === 'ar') {
        $arabic = (int) preg_match_all('/\p{Arabic}/u', $text);
        $score += min($arabic, 3000) * 0.45;
    } elseif ($lang === 'fr' || $lang === 'en') {
        $latin = (int) preg_match_all('/[\p{Latin}]/u', $text);
        $score += min($latin, 3000) * 0.3;
    }

    // Garbage penalties.
    $bad = (int) preg_match_all('/[\x{FFFD}\x{0000}-\x{0008}\x{000B}\x{000C}\x{000E}-\x{001F}]/u', $text);
    $score -= $bad * 4;
    $symbols = (int) preg_match_all('/[^\p{L}\p{N}\p{P}\s]/u', $text);
    $score -= (int) ($symbols * 0.6);

    return round(max(0, $score), 2);
}

/** HTTP POST helper returning [status, body, elapsedMs, curlError]. */
function o_http(string $url, array $fields, int $timeout, array $headers = [], ?string $jsonBody = null): array
{
    if (!function_exists('curl_init')) {
        return [0, '', 0, 'cURL is not available on this host'];
    }
    $start = microtime(true);
    $ch = curl_init($url);
    $opts = [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => $timeout,
        CURLOPT_CONNECTTIMEOUT => min(10, $timeout),
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_MAXREDIRS      => 2,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_USERAGENT      => 'SmartStudentAI-OCR/1.0',
    ];
    if ($jsonBody !== null) {
        $opts[CURLOPT_POST] = true;
        $opts[CURLOPT_POSTFIELDS] = $jsonBody;
        $headers[] = 'Content-Type: application/json';
    } elseif ($fields) {
        $opts[CURLOPT_POST] = true;
        $opts[CURLOPT_POSTFIELDS] = http_build_query($fields);
    }
    if ($headers) {
        $opts[CURLOPT_HTTPHEADER] = $headers;
    }
    curl_setopt_array($ch, $opts);
    $body = curl_exec($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = $body === false ? (curl_error($ch) ?: 'request failed') : null;
    curl_close($ch);
    return [$status, is_string($body) ? $body : '', (int) round((microtime(true) - $start) * 1000), $err];
}

/* ------------------------------------------------------------------ */
/* Providers                                                          */
/* ------------------------------------------------------------------ */

function o_lang_code(string $lang, bool $engine1 = false): string
{
    return match ($lang) {
        'ar' => 'ara',
        'fr' => 'fre',
        'en' => 'eng',
        default => $engine1 ? 'eng' : 'auto',
    };
}

/** OCR.space free endpoint (documented demo key, no signup needed). */
function o_ocrspace(string $dataUri, string $lang, int $engine, int $timeout): array
{
    $fields = [
        'apikey'               => 'helloworld',
        'base64Image'          => $dataUri,
        'language'             => o_lang_code($lang, $engine === 1),
        'isOverlayRequired'    => 'false',
        'detectOrientation'    => 'true',
        'scale'                => 'true',
        'OCREngine'            => (string) $engine,
    ];
    [$status, $body, $ms, $err] = o_http('https://api.ocr.space/parse/image', $fields, $timeout);
    if ($err !== null) {
        return ['ok' => false, 'error' => $err, 'ms' => $ms];
    }
    $decoded = json_decode($body, true);
    if (!is_array($decoded)) {
        return ['ok' => false, 'error' => 'OCR.space returned a non-JSON response (HTTP ' . $status . ')', 'ms' => $ms];
    }
    if (!empty($decoded['IsErroredOnProcessing'])) {
        $msg = $decoded['ErrorMessage'] ?? 'OCR.space could not read this image';
        if (is_array($msg)) {
            $msg = implode(' ', array_map('strval', $msg));
        }
        return ['ok' => false, 'error' => (string) $msg, 'ms' => $ms];
    }
    $parts = $decoded['ParsedResults'] ?? [];
    if (!is_array($parts)) {
        $parts = [];
    }
    $text = '';
    foreach ($parts as $part) {
        if (is_array($part) && isset($part['ParsedText'])) {
            $text .= (string) $part['ParsedText'] . "\n";
        }
    }
    return ['ok' => true, 'text' => o_clean($text), 'ms' => $ms];
}

/** Local Tesseract CLI, when the host happens to have it installed. */
function o_tesseract(string $binary, string $bytes, string $lang, int $timeout): array
{
    if (!function_exists('shell_exec') || !is_callable('shell_exec')) {
        return ['ok' => false, 'error' => 'shell_exec is disabled on this host', 'ms' => 0];
    }
    $start = microtime(true);
    $tmp = tempnam(sys_get_temp_dir(), 'ocr_');
    if ($tmp === false) {
        return ['ok' => false, 'error' => 'could not create a temp file', 'ms' => 0];
    }
    file_put_contents($tmp, $bytes);
    $langArg = match ($lang) {
        'ar' => 'ara+eng',
        'fr' => 'fra+eng',
        default => 'eng',
    };
    $cmd = escapeshellcmd($binary) . ' ' . escapeshellarg($tmp) . ' stdout -l ' . escapeshellarg($langArg)
        . ' --psm 3 2>/dev/null';
    $out = @shell_exec($cmd);
    @unlink($tmp);
    $ms = (int) round((microtime(true) - $start) * 1000);
    if (!is_string($out) || trim($out) === '') {
        return ['ok' => false, 'error' => 'Tesseract produced no text', 'ms' => $ms];
    }
    return ['ok' => true, 'text' => o_clean($out), 'ms' => $ms];
}

/** Groq vision model as a server-keyed safety net (caller still needs no key). */
function o_groq_vision(string $dataUri, string $lang, string $apiKey, int $timeout): array
{
    $langName = match ($lang) {
        'ar' => 'Arabic',
        'fr' => 'French',
        'en' => 'English',
        default => 'the original language',
    };
    $prompt = 'Read this image and return ONLY the text it contains, exactly as written, preserving line breaks. '
        . 'Do not translate, summarise or add commentary. The text is most likely in ' . $langName . '.';
    $payload = json_encode([
        'model' => 'meta-llama/llama-4-scout-17b-16e-instruct',
        'temperature' => 0,
        'messages' => [[
            'role' => 'user',
            'content' => [
                ['type' => 'text', 'text' => $prompt],
                ['type' => 'image_url', 'image_url' => ['url' => $dataUri]],
            ],
        ]],
    ], JSON_UNESCAPED_SLASHES);
    [$status, $body, $ms, $err] = o_http(
        'https://api.groq.com/openai/v1/chat/completions',
        [],
        $timeout,
        ['Authorization: Bearer ' . $apiKey],
        is_string($payload) ? $payload : null
    );
    if ($err !== null) {
        return ['ok' => false, 'error' => $err, 'ms' => $ms];
    }
    $decoded = json_decode($body, true);
    $text = $decoded['choices'][0]['message']['content'] ?? '';
    if (!is_string($text) || trim($text) === '') {
        return ['ok' => false, 'error' => 'Groq vision returned no text (HTTP ' . $status . ')', 'ms' => $ms];
    }
    return ['ok' => true, 'text' => o_clean($text), 'ms' => $ms];
}

/** Provider catalogue, in priority order. */
function o_providers(array $config): array
{
    $p = [
        [
            'id' => 'ocrspace-neural', 'label' => 'OCR.space · Neural (engine 2)',
            'tier' => 'keyless', 'timeout' => 30, 'priority' => 10,
        ],
        [
            'id' => 'ocrspace-classic', 'label' => 'OCR.space · Classic (engine 1)',
            'tier' => 'keyless', 'timeout' => 30, 'priority' => 20,
        ],
    ];

    $tesseract = null;
    // Shared hosts often disable shell functions. Guard before touching them:
    // calling a disabled function is a fatal Error in PHP 8.
    $canShell = function_exists('shell_exec') && is_callable('shell_exec')
        && function_exists('escapeshellarg');
    if ($canShell) {
        try {
            foreach (['tesseract', '/usr/bin/tesseract', '/usr/local/bin/tesseract'] as $candidate) {
                if (strpos($candidate, '/') === false) {
                    $which = @shell_exec('command -v ' . escapeshellarg($candidate) . ' 2>/dev/null');
                    if (is_string($which) && trim($which) !== '') {
                        $tesseract = trim($which);
                        break;
                    }
                } elseif (@is_executable($candidate)) {
                    $tesseract = $candidate;
                    break;
                }
            }
        } catch (Throwable $e) {
            $tesseract = null;
        }
    }
    if ($tesseract !== null) {
        $p[] = [
            'id' => 'tesseract-local', 'label' => 'Tesseract (local CLI)',
            'tier' => 'keyless', 'timeout' => 25, 'priority' => 30, 'bin' => $tesseract,
        ];
    }

    $groq = trim((string) ($config['keys']['groq'] ?? ''));
    if ($groq !== '') {
        $p[] = [
            'id' => 'groq-vision', 'label' => 'Groq · Llama 4 Scout vision',
            'tier' => 'server-key', 'timeout' => 30, 'priority' => 40,
        ];
    }
    return $p;
}

function o_stats(array $entry): void
{
    $file = o_runtime_dir() . '/ocr_stats.json';
    $fh = @fopen($file, 'c+');
    if (!$fh) {
        return;
    }
    try {
        @flock($fh, LOCK_EX);
        $raw = stream_get_contents($fh);
        $data = json_decode((string) $raw, true);
        if (!is_array($data)) {
            $data = ['total' => 0, 'providers' => [], 'recent' => []];
        }
        $data['total'] = (int) ($data['total'] ?? 0) + 1;
        $id = (string) ($entry['provider'] ?? 'none');
        $data['providers'][$id] = (int) ($data['providers'][$id] ?? 0) + 1;
        $recent = is_array($data['recent'] ?? null) ? $data['recent'] : [];
        array_unshift($recent, $entry);
        $data['recent'] = array_slice($recent, 0, 25);
        @ftruncate($fh, 0);
        @rewind($fh);
        @fwrite($fh, json_encode($data, JSON_UNESCAPED_UNICODE));
        @fflush($fh);
    } finally {
        @flock($fh, LOCK_UN);
        @fclose($fh);
    }
}

/* ------------------------------------------------------------------ */
/* Dispatch                                                           */
/* ------------------------------------------------------------------ */

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
$action = strtolower(trim((string) ($_GET['action'] ?? '')));
$in = o_body();

if ($action === 'ping' || ($method === 'GET' && $action === '')) {
    o_json([
        'ok' => true,
        'service' => 'smart-student-ai-ocr',
        'providers' => array_map(
            static fn(array $p): array => ['id' => $p['id'], 'label' => $p['label'], 'tier' => $p['tier']],
            o_providers($CONFIG)
        ),
        'time' => gmdate('c'),
    ]);
}

if ($action === 'providers') {
    o_json(['ok' => true, 'providers' => o_providers($CONFIG)]);
}

if ($method !== 'POST') {
    o_error('Method not allowed. Use POST with image_base64 or url.', 405, 'method_not_allowed');
}

$dataUri = '';
$bytes = '';

$base64 = o_str($in, 'image_base64');
if ($base64 === '') {
    $base64 = o_str($in, 'base64');
}
if ($base64 === '') {
    $base64 = o_str($in, 'image');
}
$url = o_str($in, 'url');

$mime = o_str($in, 'mime', 'image/jpeg');
if (!preg_match('#^image/[a-z0-9.+-]+$#i', $mime)) {
    $mime = 'image/jpeg';
}

if ($base64 !== '') {
    // Accept both raw base64 and a full data: URI.
    if (str_starts_with($base64, 'data:')) {
        $dataUri = $base64;
        $comma = strpos($base64, ',');
        $base64 = $comma === false ? '' : substr($base64, $comma + 1);
        if (preg_match('#^data:([^;]+);#', $dataUri, $m)) {
            $mime = $m[1];
        }
    } else {
        $dataUri = 'data:' . $mime . ';base64,' . $base64;
    }
    if (strlen($base64) > OCR_MAX_BYTES) {
        o_error('Image is too large. Please use an image under 8 MB.', 413, 'payload_too_large');
    }
    $bytes = base64_decode(preg_replace('/\s+/', '', $base64) ?? '', true) ?: '';
    if ($bytes === '') {
        o_error('image_base64 is not valid base64.', 400, 'bad_image');
    }
} elseif ($url !== '') {
    if (!preg_match('#^https?://#i', $url)) {
        o_error('url must be an http(s) URL.', 400, 'bad_url');
    }
    // Fetch the image so local providers (Tesseract) and Groq can use it too.
    [$status, $body, $ms, $err] = o_http($url, [], 20);
    if ($err !== null || $status >= 400 || $body === '') {
        o_error('Could not download that image.', 400, 'download_failed');
    }
    $bytes = $body;
    $mime = 'image/jpeg';
    $dataUri = 'data:' . $mime . ';base64,' . base64_encode($bytes);
} else {
    o_error('Send an image: POST {"image_base64": "...", "language": "ar"}', 400, 'missing_image');
}

$lang = strtolower(o_str($in, 'language', o_str($in, 'lang', 'auto')));
$lang = in_array($lang, ['ar', 'fr', 'en'], true) ? $lang : 'auto';

// Two different limits: strict per-IP OCR quota, plus a softer global guard.
if (o_rate_limited('ocr', 40)) {
    o_error('Too many OCR requests from this device. Please wait a while.', 429, 'rate_limited');
}

$providers = o_providers($CONFIG);
usort($providers, static fn(array $a, array $b): int => $a['priority'] <=> $b['priority']);

$deadline = microtime(true) + OCR_TOTAL_BUDGET;
$candidates = [];
$errors = [];

foreach ($providers as $p) {
    $remaining = $deadline - microtime(true);
    if ($remaining < 4) {
        $errors[$p['id']] = 'skipped: time budget exhausted';
        break;
    }
    $timeout = (int) max(4, min((int) $p['timeout'], (int) floor($remaining)));
    $started = microtime(true);

    switch ($p['id']) {
        case 'ocrspace-neural':
            $r = o_ocrspace($dataUri, $lang, 2, $timeout);
            break;
        case 'ocrspace-classic':
            $r = o_ocrspace($dataUri, $lang, 1, $timeout);
            break;
        case 'tesseract-local':
            $r = o_tesseract((string) $p['bin'], $bytes, $lang, $timeout);
            break;
        case 'groq-vision':
            $r = o_groq_vision($dataUri, $lang, (string) $CONFIG['keys']['groq'], $timeout);
            break;
        default:
            continue 2;
    }

    $ms = (int) $r['ms'] ?? (int) round((microtime(true) - $started) * 1000);
    if (empty($r['ok'])) {
        $errors[$p['id']] = (string) ($r['error'] ?? 'failed');
        continue;
    }

    $text = (string) ($r['text'] ?? '');
    $score = o_score($text, $lang);
    $candidates[] = [
        'provider' => $p['id'],
        'label' => $p['label'],
        'tier' => $p['tier'],
        'score' => $score,
        'chars' => mb_strlen($text),
        'ms' => $ms,
        'text' => $text,
    ];

    // A strong keyless result is enough: stop paying for more requests.
    if ($score >= OCR_GOOD_ENOUGH && $p['tier'] === 'keyless') {
        break;
    }
}

if (!$candidates) {
    o_stats([
        'provider' => 'none', 'score' => 0, 'chars' => 0,
        'lang' => $lang, 'at' => gmdate('c'), 'errors' => $errors,
    ]);
    o_json([
        'ok' => false,
        'error' => [
            'message' => 'Every OCR engine failed. Please try a clearer photo.',
            'type' => 'ocr_failed',
            'details' => $errors,
        ],
    ], 502);
}

usort($candidates, static fn(array $a, array $b): int => $b['score'] <=> $a['score']);
$best = $candidates[0];

o_stats([
    'provider' => $best['provider'], 'score' => $best['score'],
    'chars' => $best['chars'], 'lang' => $lang, 'at' => gmdate('c'),
    'tried' => array_column($candidates, 'provider'),
]);

o_json([
    'ok' => true,
    'text' => $best['text'],
    'provider' => $best['provider'],
    'provider_label' => $best['label'],
    'score' => $best['score'],
    'language' => $lang,
    'elapsed_ms' => array_sum(array_column($candidates, 'ms')),
    'candidates' => array_map(
        static fn(array $c): array => [
            'provider' => $c['provider'], 'score' => $c['score'],
            'chars' => $c['chars'], 'ms' => $c['ms'],
        ],
        $candidates
    ),
    'errors' => $errors,
]);