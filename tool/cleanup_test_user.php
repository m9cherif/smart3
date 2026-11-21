<?php
// One-off maintenance: removes the temporary test account used during setup.
// Safe to delete after running. Contains no secrets.
$c = include '/home/u170282392/domains/smart.chrif.net/public_html/db_secrets.php';
$pdo = new PDO(
    "mysql:host=localhost;dbname={$c['d']};charset=utf8mb4",
    $c['u'],
    $c['p'],
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);

$email = 'no-reply@quran.chrif.net';
$u = $pdo->prepare('SELECT id FROM users WHERE email = ?');
$u->execute([$email]);
$id = $u->fetchColumn();

if ($id) {
    foreach (['progress', 'achievements', 'xp_events', 'sessions'] as $t) {
        $pdo->prepare("DELETE FROM $t WHERE user_id = ?")->execute([$id]);
    }
    $pdo->prepare('DELETE FROM otps WHERE email = ?')->execute([$email]);
    $pdo->prepare('DELETE FROM users WHERE id = ?')->execute([$id]);
    echo "removed test user id={$id}" . PHP_EOL;
} else {
    echo 'no test user found' . PHP_EOL;
}
echo 'CLEANUP_DONE' . PHP_EOL;
