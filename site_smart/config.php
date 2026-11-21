<?php
/**
 * Smart Student AI — Auto AI Router configuration.
 *
 * This file is executed by PHP; it is never served as plain text.
 * API keys live in `keys.php` (server-only, never committed to git).
 */

$config = [
    // Optional shared secret. Leave empty to keep the router public.
    'router_token' => '',

    // Global limits
    'max_body_bytes'    => 1048576, // 1 MB
    'max_total_seconds' => 55,      // overall budget for one auto request
    'default_timeout'   => 20,      // per-provider timeout (seconds)
    'health_ttl'        => 600,     // skip a failing provider for 10 minutes
    'log_requests'      => true,

    // Account / email verification.
    'mail' => [
        'from_email'   => 'no-reply@smart.chrif.net',
        'from_name'    => 'Smart Student AI',
        'otp_length'   => 6,
        'otp_ttl'      => 600, // seconds a code stays valid
        'max_per_hour' => 6,   // max codes per email per hour
    ],
    'auth' => [
        'session_days' => 60,
    ],

    // Free-tier API keys. Fill only the ones you own; empty keys are skipped.
    'keys' => [
        'groq'              => '',
        'gemini'            => '',
        'openrouter'        => '',
        'cerebras'          => '',
        'sambanova'         => '',
        'mistral'           => '',
        'together'          => '',
        'huggingface'       => '',
        'nvidia'            => '',
        'github'            => '',
        'cloudflare_account' => '',
        'cloudflare'        => '',
        'deepinfra'         => '',
        'fireworks'         => '',
        'hyperbolic'        => '',
        'novita'            => '',
    ],
];

// Merge server-only secrets (keys.php) when present.
if (is_file(__DIR__ . '/keys.php')) {
    $extra = @include __DIR__ . '/keys.php';
    if (is_array($extra)) {
        $extraKeys = $extra['keys'] ?? $extra;
        if (is_array($extraKeys)) {
            foreach ($extraKeys as $k => $v) {
                if (is_string($v) && $v !== '') {
                    $config['keys'][$k] = $v;
                }
            }
        }
        if (!empty($extra['router_token'])) {
            $config['router_token'] = $extra['router_token'];
        }
        if (isset($extra['mail']) && is_array($extra['mail'])) {
            $config['mail'] = array_merge($config['mail'], $extra['mail']);
        }
        if (isset($extra['auth']) && is_array($extra['auth'])) {
            $config['auth'] = array_merge($config['auth'], $extra['auth']);
        }
    }
}

return $config;
