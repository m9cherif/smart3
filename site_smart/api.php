<?php
/**
 * Smart Student AI — Auto AI Router
 * OpenAI-compatible endpoint with automatic provider failover.
 *
 *   POST /v1/chat/completions   {"model":"auto","messages":[...]}
 *   GET  /v1/models
 *   GET  /health
 *   GET  /?action=ping
 */

declare(strict_types=1);

error_reporting(E_ALL);
ini_set('display_errors', '0');
ini_set('log_errors', '1');

$CONFIG = require __DIR__ . '/config.php';

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, X-Router-Token');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Max-Age: 86400');
header('X-Content-Type-Options: nosniff');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

@set_time_limit(120);
ignore_user_abort(true);

$RUNTIME = __DIR__ . '/runtime';
if (!is_dir($RUNTIME)) {
    @mkdir($RUNTIME, 0755, true);
}

/* ------------------------------------------------------------------ */
/* Providers                                                          */
/* ------------------------------------------------------------------ */

function ss_providers(array $config): array
{
    $k = $config['keys'];
    $has = static fn(string $name): bool => isset($k[$name]) && trim((string) $k[$name]) !== '';
    $p = [];

    /* ---- best available models first ------------------------------ */
    if ($has('groq')) {
        $p[] = [
            'id' => 'groq-qwen-27b', 'name' => 'Groq · Qwen 3.8 27B', 'tier' => 'free-tier',
            'url' => 'https://api.groq.com/openai/v1/chat/completions', 'model' => 'qwen/qwen3.8-27b',
            'key' => $k['groq'], 'priority' => 10, 'timeout' => 30, 'headers' => [],
        ];
        $p[] = [
            'id' => 'groq-gpt-oss-120b', 'name' => 'Groq · GPT-OSS 120B', 'tier' => 'free-tier',
            'url' => 'https://api.groq.com/openai/v1/chat/completions', 'model' => 'openai/gpt-oss-120b',
            'key' => $k['groq'], 'priority' => 11, 'timeout' => 30, 'headers' => [],
            'extra_body' => ['reasoning_effort' => 'low'],
        ];
        $p[] = [
            'id' => 'groq-allam-2-7b', 'name' => 'Groq · ALLaM 2 7B (AR)', 'tier' => 'free-tier',
            'url' => 'https://api.groq.com/openai/v1/chat/completions', 'model' => 'allam-2-7b',
            'key' => $k['groq'], 'priority' => 12, 'timeout' => 25, 'headers' => [],
        ];
    }

    /* ---- keyless providers (no auth, always available) ------------ */
    $p[] = [
        'id' => 'pollinations', 'name' => 'Pollinations AI', 'tier' => 'keyless',
        'url' => 'https://text.pollinations.ai/openai', 'model' => 'openai',
        'key' => null, 'priority' => 20, 'timeout' => 22, 'headers' => [],
    ];
    $p[] = [
        'id' => 'pollinations-fast', 'name' => 'Pollinations Fast', 'tier' => 'keyless',
        'url' => 'https://text.pollinations.ai/openai', 'model' => 'openai-fast',
        'key' => null, 'priority' => 21, 'timeout' => 22, 'headers' => [],
    ];
    $p[] = [
        'id' => 'hackclub', 'name' => 'Hack Club AI', 'tier' => 'keyless',
        'url' => 'https://ai.hackclub.com/chat/completions', 'model' => 'llama-3.3-70b-versatile',
        'key' => null, 'priority' => 22, 'timeout' => 12, 'headers' => [],
    ];

    /* ---- keyed free tiers (only if a key is configured) ----------- */

    if ($has('gemini')) {
        $p[] = [
            'id' => 'gemini-2.0-flash', 'name' => 'Google · Gemini 2.0 Flash', 'tier' => 'free-tier',
            'url' => 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
            'model' => 'gemini-2.0-flash', 'key' => $k['gemini'], 'priority' => 40, 'timeout' => 30, 'headers' => [],
        ];
    }
    if ($has('cerebras')) {
        $p[] = [
            'id' => 'cerebras-llama-3.3-70b', 'name' => 'Cerebras · Llama 3.3 70B', 'tier' => 'free-tier',
            'url' => 'https://api.cerebras.ai/v1/chat/completions', 'model' => 'llama-3.3-70b',
            'key' => $k['cerebras'], 'priority' => 50, 'timeout' => 25, 'headers' => [],
        ];
    }
    if ($has('sambanova')) {
        $p[] = [
            'id' => 'sambanova-llama-3.3-70b', 'name' => 'SambaNova · Llama 3.3 70B', 'tier' => 'free-tier',
            'url' => 'https://api.sambanova.ai/v1/chat/completions', 'model' => 'Meta-Llama-3.3-70B-Instruct',
            'key' => $k['sambanova'], 'priority' => 60, 'timeout' => 25, 'headers' => [],
        ];
    }
    if ($has('mistral')) {
        $p[] = [
            'id' => 'mistral-small', 'name' => 'Mistral AI · Small', 'tier' => 'free-tier',
            'url' => 'https://api.mistral.ai/v1/chat/completions', 'model' => 'mistral-small-latest',
            'key' => $k['mistral'], 'priority' => 70, 'timeout' => 25, 'headers' => [],
        ];
    }
    if ($has('openrouter')) {
        $p[] = [
            'id' => 'openrouter-free', 'name' => 'OpenRouter · Free models', 'tier' => 'free-tier',
            'url' => 'https://openrouter.ai/api/v1/chat/completions',
            'model' => 'meta-llama/llama-3.3-70b-instruct:free', 'key' => $k['openrouter'],
            'priority' => 80, 'timeout' => 30,
            'headers' => ['HTTP-Referer: https://smart.chrif.net', 'X-Title: Smart Student AI'],
        ];
    }
    if ($has('together')) {
        $p[] = [
            'id' => 'together-llama-free', 'name' => 'Together · Llama 3.3 70B', 'tier' => 'free-tier',
            'url' => 'https://api.together.xyz/v1/chat/completions',
            'model' => 'meta-llama/Llama-3.3-70B-Instruct-Turbo-Free',
            'key' => $k['together'], 'priority' => 90, 'timeout' => 30, 'headers' => [],
        ];
    }
    if ($has('huggingface')) {
        $p[] = [
            'id' => 'huggingface-llama-3.1-8b', 'name' => 'Hugging Face · Llama 3.1 8B', 'tier' => 'free-tier',
            'url' => 'https://router.huggingface.co/v1/chat/completions',
            'model' => 'meta-llama/Llama-3.1-8B-Instruct',
            'key' => $k['huggingface'], 'priority' => 100, 'timeout' => 30, 'headers' => [],
        ];
    }
    if ($has('nvidia')) {
        $p[] = [
            'id' => 'nvidia-llama-3.1-8b', 'name' => 'NVIDIA NIM · Llama 3.1 8B', 'tier' => 'free-tier',
            'url' => 'https://integrate.api.nvidia.com/v1/chat/completions',
            'model' => 'meta/llama-3.1-8b-instruct',
            'key' => $k['nvidia'], 'priority' => 110, 'timeout' => 30, 'headers' => [],
        ];
    }
    if ($has('github')) {
        $p[] = [
            'id' => 'github-gpt-4o-mini', 'name' => 'GitHub Models · GPT-4o mini', 'tier' => 'free-tier',
            'url' => 'https://models.github.ai/inference/chat/completions', 'model' => 'openai/gpt-4o-mini',
            'key' => $k['github'], 'priority' => 120, 'timeout' => 30, 'headers' => [],
        ];
    }
    if ($has('cloudflare') && $has('cloudflare_account')) {
        $p[] = [
            'id' => 'cloudflare-llama-3.1-8b', 'name' => 'Cloudflare Workers AI', 'tier' => 'free-tier',
            'url' => 'https://api.cloudflare.com/client/v4/accounts/' . rawurlencode((string) $k['cloudflare_account'])
                . '/ai/v1/chat/completions',
            'model' => '@cf/meta/llama-3.1-8b-instruct',
            'key' => $k['cloudflare'], 'priority' => 130, 'timeout' => 30, 'headers' => [],
        ];
    }
    if ($has('deepinfra')) {
        $p[] = [
            'id' => 'deepinfra-llama-3.1-8b', 'name' => 'DeepInfra · Llama 3.1 8B', 'tier' => 'free-tier',
            'url' => 'https://api.deepinfra.com/v1/openai/chat/completions',
            'model' => 'meta-llama/Meta-Llama-3.1-8B-Instruct',
            'key' => $k['deepinfra'], 'priority' => 140, 'timeout' => 30, 'headers' => [],
        ];
    }
    if ($has('fireworks')) {
        $p[] = [
            'id' => 'fireworks-llama-3.1-8b', 'name' => 'Fireworks · Llama 3.1 8B', 'tier' => 'free-tier',
            'url' => 'https://api.fireworks.ai/inference/v1/chat/completions',
            'model' => 'accounts/fireworks/models/llama-v3p1-8b-instruct',
            'key' => $k['fireworks'], 'priority' => 150, 'timeout' => 30, 'headers' => [],
        ];
    }
    if ($has('hyperbolic')) {
        $p[] = [
            'id' => 'hyperbolic-llama-3.3-70b', 'name' => 'Hyperbolic · Llama 3.3 70B', 'tier' => 'free-tier',
            'url' => 'https://api.hyperbolic.xyz/v1/chat/completions',
            'model' => 'meta-llama/Llama-3.3-70B-Instruct',
            'key' => $k['hyperbolic'], 'priority' => 160, 'timeout' => 30, 'headers' => [],
        ];
    }
    if ($has('novita')) {
        $p[] = [
            'id' => 'novita-llama-3.1-8b', 'name' => 'Novita AI · Llama 3.1 8B', 'tier' => 'free-tier',
            'url' => 'https://api.novita.ai/v3/openai/chat/completions',
            'model' => 'meta-llama/llama-3.1-8b-instruct',
            'key' => $k['novita'], 'priority' => 170, 'timeout' => 30, 'headers' => [],
        ];
    }

    usort($p, static fn(array $a, array $b): int => $a['priority'] <=> $b['priority']);
    return $p;
}

/* ------------------------------------------------------------------ */
/* Helpers                                                            */
/* ------------------------------------------------------------------ */

function ss_json(array $data, int $code = 200): void
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function ss_error(string $message, int $code = 400, string $type = 'invalid_request_error'): void
{
    ss_json(['error' => ['message' => $message, 'type' => $type, 'code' => $code]], $code);
}

function ss_state_load(string $runtime): array
{
    $file = $runtime . '/state.json';
    if (!is_file($file)) {
        return [];
    }
    $raw = @file_get_contents($file);
    $data = $raw !== false ? json_decode($raw, true) : null;
    return is_array($data) ? $data : [];
}

function ss_state_save(string $runtime, array $state): void
{
    @file_put_contents($runtime . '/state.json', json_encode($state, JSON_UNESCAPED_SLASHES), LOCK_EX);
}

function ss_log(string $runtime, array $entry): void
{
    $file = $runtime . '/requests.log';
    if (is_file($file) && filesize($file) > 1048576) {
        @rename($file, $runtime . '/requests.old.log');
    }
    @file_put_contents($file, json_encode($entry, JSON_UNESCAPED_SLASHES) . "\n", FILE_APPEND | LOCK_EX);
}

function ss_headers(array $provider): array
{
    $headers = ['Content-Type: application/json', 'Accept: application/json'];
    if (!empty($provider['key'])) {
        $headers[] = 'Authorization: Bearer ' . $provider['key'];
    }
    foreach (($provider['headers'] ?? []) as $h) {
        $headers[] = $h;
    }
    return $headers;
}

/**
 * POST JSON and return [httpCode, decodedBody|null, rawBody, error, latencyMs].
 */
function ss_post(string $url, array $headers, array $body, int $timeout): array
{
    $payload = json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    $start = microtime(true);

    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 8,
            CURLOPT_TIMEOUT => $timeout,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_MAXREDIRS => 2,
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_SSL_VERIFYHOST => 2,
            CURLOPT_ENCODING => '',
            CURLOPT_USERAGENT => 'SmartStudentAI-Router/1.0',
        ]);
        $raw = curl_exec($ch);
        $err = curl_error($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        $ms = (int) round((microtime(true) - $start) * 1000);
        if ($raw === false || $raw === '') {
            return [0, null, '', $err !== '' ? $err : 'empty response', $ms];
        }
        $decoded = json_decode($raw, true);
        return [$code, is_array($decoded) ? $decoded : null, $raw, $err, $ms];
    }

    // Fallback when cURL is unavailable.
    $ctx = stream_context_create([
        'http' => [
            'method' => 'POST',
            'header' => implode("\r\n", $headers),
            'content' => $payload,
            'timeout' => $timeout,
            'ignore_errors' => true,
        ],
        'ssl' => ['verify_peer' => true, 'verify_peer_name' => true],
    ]);
    $raw = @file_get_contents($url, false, $ctx);
    $ms = (int) round((microtime(true) - $start) * 1000);
    $code = 0;
    if (isset($http_response_header[0]) && preg_match('/\s(\d{3})\s/', $http_response_header[0], $m)) {
        $code = (int) $m[1];
    }
    if ($raw === false || $raw === '') {
        return [0, null, '', 'request failed', $ms];
    }
    $decoded = json_decode($raw, true);
    return [$code, is_array($decoded) ? $decoded : null, $raw, '', $ms];
}

function ss_extract_content(array $json): ?string
{
    if (isset($json['choices'][0]['message']['content'])) {
        $c = $json['choices'][0]['message']['content'];
        if (is_string($c) && trim($c) !== '') {
            return $c;
        }
        if (is_array($c)) {
            $parts = [];
            foreach ($c as $piece) {
                if (is_array($piece) && isset($piece['text'])) {
                    $parts[] = $piece['text'];
                } elseif (is_string($piece)) {
                    $parts[] = $piece;
                }
            }
            if (trim(implode('', $parts)) !== '') {
                return implode('', $parts);
            }
        }
    }
    if (isset($json['choices'][0]['text']) && is_string($json['choices'][0]['text'])) {
        return $json['choices'][0]['text'];
    }
    if (isset($json['choices'][0]['message']['reasoning_content'])) {
        $r = $json['choices'][0]['message']['reasoning_content'];
        if (is_string($r) && trim($r) !== '') {
            return $r;
        }
    }
    if (isset($json['choices'][0]['message']['reasoning'])) {
        $r = $json['choices'][0]['message']['reasoning'];
        if (is_string($r) && trim($r) !== '') {
            return $r;
        }
    }
    if (isset($json['output_text']) && is_string($json['output_text'])) {
        return $json['output_text'];
    }
    return null;
}

function ss_provider_public(array $p): array
{
    return [
        'id' => $p['id'],
        'name' => $p['name'],
        'tier' => $p['tier'],
        'model' => $p['model'],
        'priority' => $p['priority'],
    ];
}

function ss_safe_messages($messages): array
{
    if (!is_array($messages) || count($messages) === 0) {
        ss_error('`messages` must be a non-empty array.');
    }
    $out = [];
    foreach ($messages as $m) {
        if (!is_array($m) || !isset($m['role'])) {
            continue;
        }
        $role = (string) $m['role'];
        if (!in_array($role, ['system', 'user', 'assistant', 'tool', 'developer'], true)) {
            continue;
        }
        $content = $m['content'] ?? '';
        if (is_array($content)) {
            $content = json_encode($content, JSON_UNESCAPED_UNICODE);
        }
        $out[] = ['role' => $role === 'developer' ? 'system' : $role, 'content' => (string) $content];
    }
    if (count($out) === 0) {
        ss_error('No valid messages supplied.');
    }
    return $out;
}

function ss_build_payload(array $input, array $provider): array
{
    $body = ['model' => $provider['model'], 'messages' => $input['messages']];
    foreach (['temperature', 'top_p', 'stop', 'presence_penalty', 'frequency_penalty', 'seed', 'response_format', 'user'] as $field) {
        if (array_key_exists($field, $input)) {
            $body[$field] = $input[$field];
        }
    }
    $max = $input['max_completion_tokens'] ?? $input['max_tokens'] ?? 2048;
    $body['max_tokens'] = max(16, min(8192, (int) $max));
    foreach (($provider['extra_body'] ?? []) as $k => $v) {
        $body[$k] = $v;
    }
    return $body;
}

/* ------------------------------------------------------------------ */
/* Routing                                                            */
/* ------------------------------------------------------------------ */

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
$path = (string) parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
$action = strtolower((string) ($_GET['action'] ?? ''));

if ($method === 'GET' && ($action === 'models' || preg_match('#/v1/models$#', $path))) {
    $providers = ss_providers($CONFIG);
    $data = [[
        'id' => 'auto', 'object' => 'model', 'created' => 1700000000, 'owned_by' => 'smart-student-ai',
        'name' => 'Auto — best available free model',
    ]];
    foreach ($providers as $p) {
        $data[] = [
            'id' => $p['id'], 'object' => 'model', 'created' => 1700000000,
            'owned_by' => $p['tier'], 'name' => $p['name'],
        ];
    }
    ss_json(['object' => 'list', 'data' => $data]);
}

if ($method === 'GET' && ($action === 'health' || preg_match('#/(health|api/health)$#', $path))) {
    $providers = ss_providers($CONFIG);
    $state = ss_state_load($RUNTIME);
    $now = time();
    $rows = [];
    foreach ($providers as $p) {
        $s = $state[$p['id']] ?? [];
        $cooling = isset($s['fail_until']) && (int) $s['fail_until'] > $now;
        $rows[] = ss_provider_public($p) + [
            'status' => $cooling ? 'cooling' : (isset($s['last_success']) ? 'ok' : 'ready'),
            'last_success' => $s['last_success'] ?? null,
            'last_error' => $s['last_error'] ?? null,
            'last_latency_ms' => $s['last_latency_ms'] ?? null,
            'fail_until' => $cooling ? (int) $s['fail_until'] : null,
        ];
    }
    ss_json([
        'status' => 'ok',
        'router' => 'smart-student-ai',
        'version' => '1.0.0',
        'time' => gmdate('c'),
        'providers' => $rows,
        'active_keyless' => count(array_filter($rows, static fn($r) => $r['tier'] === 'keyless')),
        'active_keyed' => count(array_filter($rows, static fn($r) => $r['tier'] !== 'keyless')),
    ]);
}

if ($method === 'GET' && $action === 'ping') {
    $_SERVER['REQUEST_METHOD'] = 'POST';
    $method = 'POST';
    $GLOBALS['SS_PING'] = true;
}

if ($method === 'GET' && !$action) {
    ss_json([
        'name' => 'Smart Student AI — Auto AI Router',
        'version' => '1.0.0',
        'usage' => 'POST /v1/chat/completions with {"model":"auto","messages":[{"role":"user","content":"Hello"}]}',
        'endpoints' => ['/v1/chat/completions', '/v1/models', '/health', '/?action=ping'],
        'website' => 'https://smart.chrif.net',
    ]);
}

if ($method !== 'POST') {
    ss_error('Method not allowed.', 405);
}

/* ---- optional shared token ---------------------------------------- */
if (!empty($CONFIG['router_token'])) {
    $sent = $_SERVER['HTTP_X_ROUTER_TOKEN'] ?? '';
    if (!is_string($sent) || !hash_equals((string) $CONFIG['router_token'], $sent)) {
        ss_error('Invalid router token.', 401, 'authentication_error');
    }
}

/* ---- parse body --------------------------------------------------- */
$raw = file_get_contents('php://input');
if ($raw === false || strlen($raw) === 0) {
    if (!empty($GLOBALS['SS_PING'])) {
        $raw = json_encode([
            'model' => 'auto',
            'messages' => [['role' => 'user', 'content' => 'Reply with exactly: pong']],
            'max_tokens' => 16,
        ]);
    } else {
        ss_error('Empty request body.');
    }
}
if (strlen($raw) > (int) $CONFIG['max_body_bytes']) {
    ss_error('Request body too large.', 413);
}
$input = json_decode($raw, true);
if (!is_array($input)) {
    ss_error('Invalid JSON body.');
}
$input['messages'] = ss_safe_messages($input['messages'] ?? null);

$requested = trim((string) ($input['model'] ?? 'auto'));
$wantStream = !empty($input['stream']);

$providers = ss_providers($CONFIG);
$state = ss_state_load($RUNTIME);
$now = time();

/* ---- model selection ---------------------------------------------- */
$chain = [];
if ($requested === '' || in_array(strtolower($requested), ['auto', 'best', 'default', 'smart'], true)) {
    $chain = $providers;
} else {
    foreach ($providers as $p) {
        if ($p['id'] === $requested || $p['model'] === $requested) {
            $chain[] = $p;
        }
    }
    // "provider:model" or "provider/model" style overrides
    if (!$chain && strpos($requested, ':') !== false) {
        [$pid, $pmodel] = explode(':', $requested, 2);
        foreach ($providers as $p) {
            if ($p['id'] === $pid) {
                $p['model'] = $pmodel;
                $chain[] = $p;
            }
        }
    }
    if (!$chain) {
        ss_error('Unknown model "' . $requested . '". Use "auto" or one of the ids from /v1/models.', 404, 'model_not_found');
    }
}

/* ---- order: healthy first, cooling last --------------------------- */
$fresh = [];
$cooling = [];
foreach ($chain as $p) {
    $s = $state[$p['id']] ?? [];
    if (isset($s['fail_until']) && (int) $s['fail_until'] > $now) {
        $cooling[] = $p;
    } else {
        $fresh[] = $p;
    }
}
$order = array_merge($fresh, $cooling);

$started = microtime(true);
$attempts = [];
$chosen = null;
$result = null;
$budget = (int) $CONFIG['max_total_seconds'];

foreach ($order as $provider) {
    $elapsed = microtime(true) - $started;
    if ($elapsed >= $budget - 3) {
        $attempts[] = ['provider' => $provider['id'], 'error' => 'skipped: global time budget reached'];
        break;
    }
    $timeout = (int) min($provider['timeout'], max(5, $budget - $elapsed - 2));

    $payload = ss_build_payload($input, $provider);
    [$code, $json, $body, $err, $ms] = ss_post($provider['url'], ss_headers($provider), $payload, $timeout);

    $content = $json ? ss_extract_content($json) : null;

    if ($code >= 200 && $code < 300 && $content !== null) {
        $chosen = $provider;
        $result = [
            'id' => 'chatcmpl-' . bin2hex(random_bytes(10)),
            'object' => 'chat.completion',
            'created' => time(),
            'model' => $provider['model'],
            'choices' => [[
                'index' => 0,
                'message' => ['role' => 'assistant', 'content' => $content],
                'finish_reason' => $json['choices'][0]['finish_reason'] ?? 'stop',
            ]],
            'usage' => $json['usage'] ?? ['prompt_tokens' => 0, 'completion_tokens' => 0, 'total_tokens' => 0],
            'x_router' => [
                'requested_model' => $requested,
                'provider' => $provider['id'],
                'provider_name' => $provider['name'],
                'tier' => $provider['tier'],
                'attempts' => count($attempts) + 1,
                'latency_ms' => $ms,
                'fallbacks' => $attempts,
            ],
        ];
        $state[$provider['id']] = [
            'last_success' => gmdate('c'),
            'last_latency_ms' => $ms,
            'last_error' => null,
        ];
        ss_state_save($RUNTIME, $state);
        break;
    }

    $reason = $err !== '' ? $err : ('HTTP ' . $code);
    if ($json && isset($json['error']['message'])) {
        $reason = 'HTTP ' . $code . ': ' . substr((string) $json['error']['message'], 0, 300);
    } elseif ($code === 0 && $body !== '') {
        $reason = 'transport error: ' . substr(strip_tags($body), 0, 160);
    }
    $attempts[] = ['provider' => $provider['id'], 'error' => $reason, 'latency_ms' => $ms];
    // Rate limits recover quickly; other failures cool down longer.
    $cooldown = (int) $CONFIG['health_ttl'];
    if (preg_match('/\b(402|429)\b|limit|rate|quota|too many/i', $reason)) {
        $cooldown = 60;
    }
    $state[$provider['id']] = [
        'last_success' => $state[$provider['id']]['last_success'] ?? null,
        'last_latency_ms' => $ms,
        'last_error' => $reason,
        'fail_until' => time() + $cooldown,
    ];
    ss_state_save($RUNTIME, $state);
}

if (!empty($CONFIG['log_requests'])) {
    ss_log($RUNTIME, [
        'ts' => gmdate('c'),
        'ip' => $_SERVER['REMOTE_ADDR'] ?? '',
        'model' => $requested,
        'provider' => $chosen['id'] ?? null,
        'ok' => $result !== null,
        'attempts' => count($attempts) + ($result ? 1 : 0),
        'ms' => (int) round((microtime(true) - $started) * 1000),
    ]);
}

if ($result === null) {
    ss_json([
        'error' => [
            'message' => 'All AI providers failed. Please retry in a moment.',
            'type' => 'upstream_error',
            'code' => 502,
            'attempts' => $attempts,
        ],
    ], 502);
}

header('X-Router-Provider: ' . $chosen['id']);
header('X-Router-Attempts: ' . (count($attempts) + 1));
header('X-Router-Latency-Ms: ' . $result['x_router']['latency_ms']);

if ($wantStream) {
    header('Content-Type: text/event-stream; charset=utf-8');
    header('Cache-Control: no-cache');
    $text = $result['choices'][0]['message']['content'];
    $chunk = [
        'id' => $result['id'], 'object' => 'chat.completion.chunk', 'created' => $result['created'],
        'model' => $result['model'],
        'choices' => [['index' => 0, 'delta' => ['role' => 'assistant', 'content' => $text], 'finish_reason' => null]],
    ];
    echo 'data: ' . json_encode($chunk, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n\n";
    $done = [
        'id' => $result['id'], 'object' => 'chat.completion.chunk', 'created' => $result['created'],
        'model' => $result['model'],
        'choices' => [['index' => 0, 'delta' => new stdClass(), 'finish_reason' => 'stop']],
    ];
    echo 'data: ' . json_encode($done, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n\n";
    echo "data: [DONE]\n\n";
    exit;
}

ss_json($result);
