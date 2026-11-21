<?php
// Temporary diagnostic: send several mail variants to pinpoint what breaks delivery.
$to = 'no-reply@quran.chrif.net';
$from = 'no-reply@smart.chrif.net';

$b = '=_x' . bin2hex(random_bytes(4));
$body = "--$b\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\nplain part\r\n"
      . "--$b\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n<p>html part</p>\r\n"
      . "--$b--";

$mpHeaders = "MIME-Version: 1.0\r\nFrom: Smart <$from>\r\nContent-Type: multipart/alternative; boundary=\"$b\"";

// A: multipart + -f + Return-Path (current implementation)
$a = mail($to, 'PROBE A mp+f+rp', $body, $mpHeaders . "\r\nReturn-Path: $from", '-f' . $from);
// B: multipart, no -f, no Return-Path
$bh = mail($to, 'PROBE B mp plain', $body, $mpHeaders);
// C: simple + -f
$c = mail($to, 'PROBE C simple+f', 'simple body', "From: $from", '-f' . $from);
// D: multipart + -f, no Return-Path
$d = mail($to, 'PROBE D mp+f', $body, $mpHeaders, '-f' . $from);

echo 'A=' . var_export($a, true) . ' B=' . var_export($bh, true)
   . ' C=' . var_export($c, true) . ' D=' . var_export($d, true) . PHP_EOL;
echo 'sendmail_path=' . ini_get('sendmail_path') . PHP_EOL;
echo 'PROBE_DONE' . PHP_EOL;
