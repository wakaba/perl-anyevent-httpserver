use strict;
BEGIN {
  my $dir_name = __FILE__; $dir_name =~ s{[^/\\]+$}{};
  $dir_name ||= '.';
  require $dir_name . "/../lib/httpserver.pl";
}
use warnings;
use Digest::MD5 qw(md5_hex); # perl 5.7.3+
use File::Temp;

my $port = shift or die "Usage: $0 port";

my $temp_dir = File::Temp->newdir;

warn "Cache directory: $temp_dir\n";
 
my $server = HTTPServer->new
    (host => '127.0.0.1', port => $port,
     request_handler => sub {
       my $self = shift;
       my $url = $self->url;

       my $file_name = $temp_dir->dirname . '/' . md5_hex $url;
       if (-f $file_name) {
         warn "Cache for URL <$url> ($file_name) found\n";
       } else {
         warn "Cache for URL <$url> ($file_name) not found\n";
         system "curl --max-redirs 5 --location \Q$url\E > \Q$file_name\E";
         unlink $file_name if $? >> 8;
       }
       if (-f $file_name) {
         open my $file, '<', $file_name or $self->send_error_response (500);
         $self->http_handle->push_write("HTTP/1.0 200 OK\x0D\x0A\x0D\x0A");
         # XXX can't preserve server's response code...
         local $/ = undef;
         $self->http_handle->push_write(<$file>);
       } else {
         ## URL error, DNS error, ... (not an HTTP server error)
         $self->send_error_response (500);
       }
       $self->destroy;
       return 1;
     }); # request_handler

my $sig = AE::signal 'INT' => sub {
  warn "Stopped\n";
  $server->stop;
};

$server->listen;
$server->run;

=head1 AUTHOR

Wakaba <wakaba@suikawiki.org>.

=head1 LICENSE

Copyright 2012 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
