#!/bin/ksh

set -eu

MIRROR_HOST=${MIRROR_HOST-dl.mroach.com}
MIRROR_PATH=${MIRROR_PATH-/irix}

if [ `whoami` != "root" ]; then
  echo "must be run as root" >&2
  exit 1
fi

[ -d /opt/bin ] || mkdir /opt/bin
[ -d /opt/var/ipm ] || mkdir -p /opt/var/ipm
[ -d /var/cache/ipm ] || mkdir -p /var/cache/ipm

echo "Creating http_get.pl"
cat <<'EOF' > http_get.pl
#!/usr/bin/env perl

# C 2005, 2008, 2014-2016 SPINLOCK Solutions
use IO::Socket;

sub http_get {
  my ( $host, $file, $out, $force ) = @_;

  # Support for using this function to download files from mirrors which
  # include a subdirectory. In such cases, the subdir must become a part
  # of path, not hostname.
  if ( $host =~ s#(/.*)## ) { $file = $1 . $file; }

  print STDERR "Downloading http://$host$file, size: ";
  my $socket = IO::Socket::INET->new(
    PeerAddr => $host,
    PeerPort => 'http(80)',
    Proto    => 'tcp',
  ) or die("Can't create IO::Socket::INET object ($!); exiting.");
  $socket->autoflush(1);
  binmode $socket;

  print( $socket
        "GET $file HTTP/1.0\r\nHost: $host\r\nUser-Agent: Mozilla/5.0 (iports)\r\n\r\n" );
  my $line;
  my $len = 0;

  while ( defined( $line = <$socket> ) ) {
    if ( $len and $line =~ /^\s*$/ ) { last }
    elsif ( $line =~ /^content-length:\s*(\d+)\s*$/i ) {
      $len = $1;
      my $len_fmt = sprintf '%.2f', $len / 1e6;
      print STDERR "$len_fmt MB\n";

      if ( !$force and -e "$out" and ( stat("$out") )[7] == $len ) {
        print STDERR "  ($file already downloaded to $out; skipping.)\n";
        goto NEXT_FILE;
      }

      open OUT, "> $out" or die "Can't wropen '$out' ($!); exiting.\n";
      binmode OUT;
    }
  }
  if ( !$len ) { die "Error downloading $_; exiting.\n"; }

  my $data;
  my $downloaded = 0;
  my $chunk      = 0;
  my $len_fmt    = '0.00';
  while ( defined( $data = <$socket> ) ) {
    my $len = length($data);
    $chunk      += $len;
    $downloaded += $len;
    if ( $chunk >= 1024 * 128 ) {
      $chunk   = 0;
      $len_fmt = sprintf '%.2f', $downloaded / 1e6;
    }
    print OUT $data;
  }
  $len_fmt = sprintf '%.2f', $downloaded / 1e6;

  close OUT or warn "Can't wrclose '$out' ($!); ignoring and continuing.\n";

  NEXT_FILE:
    close $socket;
}

http_get( "$ARGV[0]", "$ARGV[1]", "$ARGV[2]", 1 );
EOF

PATH=/opt/bin:$PATH

chmod +x http_get.pl
mv http_get.pl /opt/bin/.

echo "Fetching ipm"
http_get.pl $MIRROR_HOST $MIRROR_PATH/ipm.sh ipm.sh
chmod +x ipm.sh
mv ipm.sh /opt/bin/ipm

echo "Fetching latest package index"
http_get.pl $MIRROR_HOST $MIRROR_PATH/pkg/index.csv index.csv
mv index.csv /opt/var/ipm/.

# pre-fill the cache with the packages we need to install curl
echo "Fetching base dependencies"
for dep in curl openssl zlib sqlite; do
  file=`grep "^$dep," /opt/var/ipm/index.csv | cut -d, -f3`
  http_get.pl $MIRROR_HOST $MIRROR_PATH/pkg/$file $file
  mv $file /var/cache/ipm/.
done

http_get.pl $MIRROR_HOST $MIRROR_PATH/libgcc_s.so.1 libgcc_s.so.1
mv libgcc_s.so.1 /opt/lib32/.

echo "Installing curl and sqlite"
ipm install curl
ipm install sqlite

cat <<-'EOF'

Bootstrapped and ready to go. You should make modifications to your environment
variables to easily use IPM:

    PATH=$PATH:/opt/bin:/opt/local/bin
    MANPATH=${MANPATH-}:/opt/local/share/man
EOF
