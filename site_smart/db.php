<?php
declare(strict_types=1);

/**
 * Smart Student AI — database layer (MySQL via PDO).
 *
 * Connection credentials live in `db_secrets.php` (server-only, never
 * committed to git). Expected shape:
 *
 *   <?php return ['u' => 'u170282392_smart', 'p' => 'secret', 'd' => 'u170282392_smart'];
 *
 * Long keys (`user`, `pass`, `db`, `host`) are also accepted.
 */

function ss_db_config(): array
{
    $cfg = [
        'host'    => 'localhost',
        'user'    => '',
        'pass'    => '',
        'db'      => '',
        'charset' => 'utf8mb4',
    ];

    $file = __DIR__ . '/db_secrets.php';
    if (is_file($file)) {
        $extra = @include $file;
        if (is_array($extra)) {
            foreach (['u' => 'user', 'p' => 'pass', 'd' => 'db', 'h' => 'host'] as $short => $long) {
                if (!empty($extra[$short]) && is_string($extra[$short])) {
                    $cfg[$long] = $extra[$short];
                }
                if (!empty($extra[$long]) && is_string($extra[$long])) {
                    $cfg[$long] = $extra[$long];
                }
            }
        }
    }

    return $cfg;
}

/**
 * Returns a shared PDO connection, or null when the database is not
 * configured / unreachable. Never throws.
 */
function ss_db(): ?PDO
{
    static $pdo = null;
    static $tried = false;
    if ($tried) {
        return $pdo;
    }
    $tried = true;

    $cfg = ss_db_config();
    if ($cfg['db'] === '' || $cfg['user'] === '') {
        return null;
    }

    try {
        $dsn = sprintf('mysql:host=%s;dbname=%s;charset=%s', $cfg['host'], $cfg['db'], $cfg['charset']);
        $pdo = new PDO($dsn, $cfg['user'], $cfg['pass'], [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
    } catch (Throwable $e) {
        $pdo = null;
    }

    return $pdo;
}

/**
 * Creates every table used by the app if it does not exist yet.
 * Safe to call on every request.
 */
function ss_db_init(PDO $pdo): void
{
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS users (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT,
            name VARCHAR(80) NOT NULL,
            email VARCHAR(190) NOT NULL,
            password_hash VARCHAR(255) NOT NULL,
            verified TINYINT(1) NOT NULL DEFAULT 0,
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL,
            PRIMARY KEY (id),
            UNIQUE KEY uniq_email (email)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
    );

    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS otps (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            email VARCHAR(190) NOT NULL,
            code_hash CHAR(64) NOT NULL,
            purpose VARCHAR(16) NOT NULL DEFAULT \'verify\',
            attempts INT NOT NULL DEFAULT 0,
            consumed TINYINT(1) NOT NULL DEFAULT 0,
            expires_at DATETIME NOT NULL,
            created_at DATETIME NOT NULL,
            PRIMARY KEY (id),
            KEY idx_email_purpose (email, purpose)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
    );

    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS sessions (
            token_hash CHAR(64) NOT NULL,
            user_id INT UNSIGNED NOT NULL,
            created_at DATETIME NOT NULL,
            expires_at DATETIME NOT NULL,
            last_seen DATETIME NOT NULL,
            PRIMARY KEY (token_hash),
            KEY idx_user (user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
    );

    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS progress (
            user_id INT UNSIGNED NOT NULL,
            xp INT NOT NULL DEFAULT 0,
            level INT NOT NULL DEFAULT 1,
            revision_count INT NOT NULL DEFAULT 0,
            dictation_count INT NOT NULL DEFAULT 0,
            best_score INT NOT NULL DEFAULT 0,
            streak INT NOT NULL DEFAULT 0,
            longest_streak INT NOT NULL DEFAULT 0,
            last_active DATE NULL,
            daily_goal INT NOT NULL DEFAULT 50,
            today_xp INT NOT NULL DEFAULT 0,
            updated_at DATETIME NOT NULL,
            PRIMARY KEY (user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
    );

    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS achievements (
            user_id INT UNSIGNED NOT NULL,
            code VARCHAR(64) NOT NULL,
            unlocked_at DATETIME NOT NULL,
            PRIMARY KEY (user_id, code)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
    );

    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS xp_events (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            user_id INT UNSIGNED NOT NULL,
            xp INT NOT NULL,
            source VARCHAR(32) NOT NULL,
            created_at DATETIME NOT NULL,
            PRIMARY KEY (id),
            KEY idx_user_date (user_id, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
    );
}

/** Number of XP required to advance one level (mirrors the app). */
const SS_XP_PER_LEVEL = 100;

function ss_level_for_xp(int $xp): int
{
    return intdiv(max(0, $xp), SS_XP_PER_LEVEL) + 1;
}
