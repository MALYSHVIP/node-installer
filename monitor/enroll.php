<?php
declare(strict_types=1);

/* Only public node certificates and proofs cross this endpoint. The node's
 * private key and panel SECRET_KEY must never be sent here. */
function enrollmentReply(array $server, string $raw, array $tokens, array $peers, string $ca): array {
    $deny = static fn(int $code): array => [$code, ['ok' => false]];
    $ip = (string) ($server['REMOTE_ADDR'] ?? '');
    if (!filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4 | FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE) ||
        !in_array($ip, $peers, true) || !isset($tokens[$ip]) ||
        !is_string($tokens[$ip]) || !preg_match('/^[a-f0-9]{64}$/D', $tokens[$ip])) return $deny(403);
    $key = hex2bin($tokens[$ip]);
    $message = static fn(string $stamp, string $nonce): string => "node-enroll-v1\n$ip\n$stamp\n$nonce";
    $method = (string) ($server['REQUEST_METHOD'] ?? '');
    if ($method === 'GET') {
        $stamp = (string) time();
        $nonce = bin2hex(random_bytes(32));
        return [200, ['ip' => $ip, 'time' => $stamp, 'nonce' => $nonce,
            'challenge' => hash_hmac('sha256', $message($stamp, $nonce), $key)]];
    }
    if ($method !== 'POST') return $deny(405);
    if (strlen($raw) < 1 || strlen($raw) > 16384) return $deny(413);
    $data = json_decode($raw, true);
    if (!is_array($data) || ($data['ip'] ?? '') !== $ip) return $deny(403);
    foreach (['time', 'nonce', 'challenge', 'certificate', 'proof'] as $field) {
        if (!isset($data[$field]) || !is_string($data[$field])) return $deny(400);
    }
    $stamp = $data['time']; $nonce = $data['nonce'];
    if (!preg_match('/^[0-9]{10}$/D', $stamp) || abs(time() - (int) $stamp) > 180 ||
        !preg_match('/^[a-f0-9]{64}$/D', $nonce) ||
        !preg_match('/^[a-f0-9]{64}$/D', $data['challenge']) ||
        !hash_equals(hash_hmac('sha256', $message($stamp, $nonce), $key), $data['challenge'])) return $deny(403);
    if (strlen($data['certificate']) > 8192 || strlen($data['proof']) > 1024) return $deny(400);
    $cert = @openssl_x509_read($data['certificate']);
    $parsed = $cert === false ? false : @openssl_x509_parse($cert);
    if (!is_array($parsed) || ($parsed['validFrom_time_t'] ?? PHP_INT_MAX) > time() ||
        ($parsed['validTo_time_t'] ?? 0) <= time() ||
        str_contains((string) ($parsed['extensions']['basicConstraints'] ?? ''), 'CA:TRUE') ||
        @openssl_x509_checkpurpose($cert, X509_PURPOSE_SSL_SERVER, [$ca]) !== true) return $deny(403);
    $proof = base64_decode($data['proof'], true);
    $signed = $message($stamp, $nonce) . "\n" . $data['challenge'];
    if ($proof === false || @openssl_verify($signed, $proof, $cert, OPENSSL_ALGO_SHA256) !== 1) return $deny(403);
    return [200, ['ip' => $ip, 'token' => $tokens[$ip],
        'signing_public_key_sha256' => '0e2d38540c5c693a8ce4d2c5a39bafa8089c5b06d03caa309a1e4a250660cba9']];
}

if (defined('REMNANODE_ENROLL_LIBRARY_ONLY')) return;
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('Content-Type: application/json; charset=utf-8');
try {
    $tokens = json_decode((string) @file_get_contents('/etc/monitor-ssh-peers/tokens.json'), true);
    $manifest = json_decode((string) @file_get_contents(__DIR__ . '/manifest.json'), true);
    $peers = $manifest['payload']['peers'] ?? null;
    if (!is_array($tokens) || !is_array($peers)) throw new RuntimeException('registry unavailable');
    [$status, $body] = enrollmentReply($_SERVER,
        (string) file_get_contents('php://input', false, null, 0, 16385),
        $tokens, $peers, '/etc/monitor-ssh-peers/panel-ca.pem');
    http_response_code($status);
    echo json_encode($body, JSON_THROW_ON_ERROR);
} catch (Throwable $error) {
    http_response_code(503);
    echo '{"ok":false}';
}
