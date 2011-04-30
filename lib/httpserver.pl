#!/usr/bin/perl
use strict;
use warnings;

=head1 NAME

httpserver.pl - A simple broken HTTP server with CGI support

=head1 SYNOPSIS

  require 'httpserver.pl';
  
  my $server = HTTPServer->new
      (host => '0', port => 8080,
       request_handler => sub {
         my $self = shift;
         my $url = $self->url;
         my $path;
         if ($url eq 'abc') {
           $path = '/path/to/abc.cgi';
	   $self->handle_by_cgi ($path);
	   return 1;
         } elsif ($url eq '/xyz') {
           $path = '/path/to/xyz.cgi';
           $self->handle_by_cgi ($path);
           return 1;
         }
         return 0;
       }); # request_handler
  
  $server->debug_mode;
  $server->listen;
  $server->run;

=head1 DESCRIPTION

This script, C<httpserver.pl>, is a simple non-conforming
(i.e. broken) HTTP server implemented using C<AnyEvent>.  It supports
CGI, or in fact it only supports CGI as a way to generate responses,
but it is again non-conforming such that your favorite CGI script
would not run.  This script should not be used for any kind of
product.

=cut

package HTTPServer;
use strict;
use warnings;
our $VERSION = '1.0';
use IO::Handle;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

sub new ($;%) {
  my $class = shift;
  return bless {@_}, $class;
} # new

sub host ($;$) {
  my $self = shift;
  if (@_) {
    $self->{host} = shift;
  }
  return $self->{host};
} # host

sub port ($;$) {
  my $self = shift;
  if (@_) {
    $self->{port} = shift;
  }
  return $self->{port};
} # port

sub request_handler ($;$) {
  my $self = shift;
  if (@_) {
    $self->{request_handler} = shift;
  }
  return $self->{request_handler};
} # request_handler

sub listen ($) {
  my $self = shift;
  tcp_server $self->host, $self->port, sub {
    my ($sock, $host, $port) = @_;
    $sock->autoflush (1);
    warn "C->S: $host:$port: Connected\n";
    
    my $req = HTTPServer::RequestHandler->new
	(request_handler => $self->request_handler);
    my $handle = AnyEvent::Handle->new
	(fh => $sock,
	 on_read => sub {
	   my ($handle) = @_;
	   warn "C->S: Received invalid data\n";
	   unless ($req->{response_header_sent}) {
	     $req->send_error_response (400);
	   }
	   $req->destroy;
	 }, # on_read
	 on_error => sub {
	   my ($handle, $fatal, $msg) = @_;
	   warn "C->S: Error: $msg\n";
	   $req->destroy;
	 }, # on_error
	 on_eof => sub {
	   my ($handle) = @_;
	   warn "C->S: EOF\n";
	   $req->destroy;
	 }); # on_eof
    $handle->push_read
	(line => "\x0D\x0A" => sub {
	   $req->consume_http_request_line (@_);
	 });
    $req->http_handle ($handle);
  }, sub {
    my ($fh, $host, $port) = @_;
    warn "S: $host:$port: Start listening\n";
  };
} # listen

sub run ($) {
  AnyEvent->condvar->recv;
} #run

sub debug_mode ($) {
  no warnings 'redefine';
  my $orig_destroy = AnyEvent::Handle->can ('DESTROY');
  *AnyEvent::Handle::DESTROY = sub {
    $orig_destroy->(@_);
    warn ref $_[0], "->DESTROY\n";
  }; # DESTROY
} # debug_mode

1;

package HTTPServer::RequestHandler;
use strict;
use warnings;
our $VERSION = '1.0';
use AnyEvent::Run;

sub new ($;%) {
  my $class = shift;
  return bless {@_}, $class;
} # new

sub method ($;$) {
  my $self = shift;
  if (@_) {
    $self->{method} = shift;
  }
  return $self->{method};
} # method

sub url ($;$) {
  my $self = shift;
  if (@_) {
    $self->{url} = shift;
  }
  return $self->{url};
} # url

sub http_version ($;$) {
  my $self = shift;
  if (@_) {
    my $v = shift;
    if ($v =~ /\A([0-9]+)\.([0-9]+)\z/) {
      $self->{http_version} = sprintf '%d.%d', 0+$1, 0+$2;
    }
  }
  return $self->{http_version} || '0.9';
} # http_version

sub is_http0 ($) {
  my $self = shift;
  return $self->http_version < 1.0;
} # is_http0

sub is_http1 ($) {
  my $self = shift;
  return ($self->http_version >= 1.0 and $self->http_version < 2.0)
} # is_http1

sub http_handle ($;$) {
  my $self = shift;
  if (@_) {
    $self->{http_handle} = shift;
  }
  return $self->{http_handle};
} # http_handle

sub cgi_handle ($;$) {
  my $self = shift;
  if (@_) {
    $self->{cgi_handle} = shift;
  }
  return $self->{cgi_handle};
} # cgi_handle

sub consume_http_request_line ($$$) {
  my ($self, $handle, $line) = @_;
  warn "C->S: |$line|\n";
  if ($line =~ /\A(\S+)\s+(\S+)\s+HTTP\/([0-9.]+)\z/) {
    $self->method ($1);
    $self->url ($2);
    $self->http_version ($3);
  } elsif ($line =~ /\A(\S+)\s+(\S+)\z/) {
    $self->method ($1);
    $self->url ($2);
    $self->http_version ('0.9');
  } else {
    $self->send_error_response (400);
    return $self->destroy;
  }

  if ($self->is_http1) {
    $self->http_handle->unshift_read
	(line => "\x0D\x0A", sub {
	   $self->consume_http_header_line (@_);
	 });
  } elsif ($self->is_http0) {
    unless ($self->handle_request) {
      $self->send_error_response (404);
      return $self->destroy;
    }
  } else {
    $self->send_error_response (505);
    return $self->destroy;
  }
} # consume_http_request_line

sub consume_http_header_line ($$$) {
  my ($self, $handle, $line) = @_;
  warn "C->S: |$line|\n";
  if ($line eq '') {
    unless ($self->handle_request) {
      $self->send_error_response (404);
      return $self->destroy;
    }
  } else {
    $self->http_handle->unshift_read
	(line => "\x0D\x0A", sub {
	   $self->consume_http_header_line (@_);
	 });
  }
} # consume_http_header_line

sub consume_cgi_header_line ($$$) {
  my ($self, $whandle, $line) = @_;
  warn "CGI->S: |$line|\n";
  my $cgi_header = $self->{cgi_header};
  if ($line eq '') {
    if ($self->is_http1) {
      my $line = 'HTTP/1.0 ' .
	  (exists $cgi_header->{status} ? $cgi_header->{status} : '200 OK');
      delete $cgi_header->{status};
      warn "S->C: |$line|\n";
      my $http_handle = $self->http_handle;
      $http_handle->push_write ($line . "\x0D\x0A");
      for my $field_name (keys %{$cgi_header}) {
	my $line = $field_name . ': ' . $cgi_header->{$field_name};
	warn "S->C: |$line|\n";
	$http_handle->push_write ($line . "\x0D\x0A");
      }
      $http_handle->push_write ("\x0D\x0A");
      $self->{response_header_sent} = 1;
    } else {
      $self->{response_header_sent} = 1;
    }
  } else {
    if ($line =~ s/^([^:]+?)\s*\:\s*//) {
      my $field_name = $1;
      $field_name =~ tr/A-Z/a-z/;
      if (defined $cgi_header->{$field_name}) {
	$cgi_header->{$field_name} .= ',' . $line;
      } else {
	$cgi_header->{$field_name} = $line;
      }
    }
    $self->cgi_handle->push_read
	(line => "\n", sub {
	   $self->consume_cgi_header_line (@_);
	 });
  }
} # consume_cgi_header_line

sub handle_request ($) {
  my $self = shift;
  my $code = $self->{request_handler} || sub { 0 };
  return $code->($self);
} # handle_request

sub handle_by_cgi ($$) {
  my ($self, $path) = @_;
  warn "S->CGI: Execute |$path|\n";
  $self->{cgi_header} = {};
  my $handle = AnyEvent::Run->new
      (cmd => [$path],
       on_read => sub {
	 my $whandle = shift;
	 $self->http_handle->push_write ($whandle->rbuf);
	 $whandle->rbuf = '';
       },
       on_error => sub {
	 my ($whandle, $fatal, $msg) = @_;
	 warn "CGI->S: Error: $msg\n";
	 unless ($self->{response_header_sent}) {
	   $self->send_error_response (500);
	 }
	 $self->destroy;
       },
       on_eof => sub {
	 my $whandle = shift;
	 warn "CGI->S: EOF\n";
	 unless ($self->{response_header_sent}) {
	   $self->send_error_response (500);
	 }
	 $self->destroy;
       });
  $self->cgi_handle ($handle);
  $self->cgi_handle->push_read
      (line => "\n", sub {
	 $self->consume_cgi_header_line (@_);
       });
} # handle_by_cgi

sub send_error_response ($$) {
  my ($self, $code) = @_;

  my $message = {
    400 => 'Bad Request',
    404 => 'Not Found',
    405 => 'Method Not Implemented',
    500 => 'Internal Server Error',
    505 => 'HTTP Version Not Supported',
  }->{$code} || $code;
  
  my $response_line = 'HTTP/1.0 ' . $code . ' ' . $message;
  warn "S->C: |$response_line|\n";
  $self->http_handle->push_write ($response_line . "\x0D\x0A\x0D\x0A");
} # send_error_response

sub destroy ($) {
  my $self = shift;

  $self->{cgi_handle}->destroy if $self->{cgi_handle};
  delete $self->{cgi_handle};

  $self->{http_handle}->destroy if $self->{http_handle};
  delete $self->{http_handle};
} # destroy

sub DESTROY {
  warn ref $_[0], "->DESTROY\n";
} # DESTROY

1;

=head1 AUTHOR

Wakaba <w@suika.fam.cx>.

=head1 LICENSE

Copyright 2011 Wakaba <w@suika.fam.cx>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
