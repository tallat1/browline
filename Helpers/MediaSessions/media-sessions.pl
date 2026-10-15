#!/usr/bin/perl
# Notch çoklu medya oturumu yardımcısı: MediaSessions.dylib'i yükler ve istenen işlevi çağırır.
# Kullanım: media-sessions.pl <dylib> stream
#           media-sessions.pl <dylib> send <pid> <komut>
#           media-sessions.pl <dylib> seek <pid> <mikrosaniye>
# /usr/bin/perl'in bundle kimliği com.apple. ile başladığı için mediaremoted ona yanıt veriyor.
use strict;
use warnings;
use DynaLoader;

my $library = shift @ARGV or die "media-sessions: kitaplık yolu eksik\n";
my $command = shift @ARGV or die "media-sessions: komut eksik\n";
my %symbols = (stream => "sessions_stream", send => "sessions_send", seek => "sessions_seek");
my $symbol = $symbols{$command} or die "media-sessions: bilinmeyen komut '$command'\n";

if ($command eq "send" || $command eq "seek") {
  my ($pid, $value) = @ARGV;
  die "media-sessions: süreç kimliği ve değer gerekli\n"
    unless defined $value && $pid =~ /^\d+$/ && $value =~ /^\d+$/;
  $ENV{NOTCH_SESSIONS_PID} = $pid;
  $ENV{NOTCH_SESSIONS_VALUE} = $value;
}

my $handle = DynaLoader::dl_load_file($library, 0)
  or die "media-sessions: yüklenemedi: " . DynaLoader::dl_error() . "\n";
my $address = DynaLoader::dl_find_symbol($handle, $symbol)
  or die "media-sessions: '$symbol' bulunamadı\n";
DynaLoader::dl_install_xsub("main::run", $address);
main::run();
