use strict;
use warnings;
my $dir_name = __FILE__;
$dir_name =~ s{[^/\\]+$}{};
$dir_name ||= '.';
$dir_name .= '/../lib';
require $dir_name . '/httpserver.pl';
my $base_path = shift or die "base_path not specified";
my $port = shift or die "port not specified";

my $server = HTTPServer->new(
    host => '0',
    port => $port,
    request_handler => sub {
        my $self = shift;
        my $url = $self->url;
        my @path = grep { length } split m{/}, $url; # unsafe!
        my $file_name = join '/', $base_path, @path; # unsafe!
        warn "GET $url -> $file_name\n";
        if (-f $file_name) {
            open my $file, '<', $file_name or $self->send_error_response(404);
            $self->http_handle->push_write("HTTP/1.0 200 OK\x0D\x0AContent-Type: text/html; charset=utf-8\x0D\x0A\x0D\x0A");
            while (<$file>) {
                $self->http_handle->push_write($_);
            }
        } else {
            $self->send_error_response(404);
        }
        $self->destroy;
        return 1;
    },
); # request_handler

$server->debug_mode;
$server->listen;
$server->run;
