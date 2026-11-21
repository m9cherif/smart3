<?php
// Server-side deploy helper for smart.chrif.net.
// Invoked by a one-shot Hostinger cron job; pulls the site files from GitHub raw.
// Contains no secrets.

$root = '/home/u170282392/domains/smart.chrif.net/public_html';
$base = 'https://raw.githubusercontent.com/m9cherif/smart3/master/site_smart/';
$files = ['index.html', 'api.php', 'auth.php', 'db.php', 'config.php', '.htaccess', 'runtime/.htaccess'];

@mkdir($root . '/runtime', 0755, true);

foreach ($files as $f) {
    $target = $root . '/' . $f;
    $ok = @copy($base . $f, $target);
    fwrite(STDOUT, $f . ': ' . ($ok ? 'ok' : 'FAIL') . PHP_EOL);
}

fwrite(STDOUT, 'files in public_html: ' . implode(', ', @scandir($root) ?: []) . PHP_EOL);
fwrite(STDOUT, 'ROUTER_DEPLOY_DONE' . PHP_EOL);
