package Tatsumaki::Service::IRC;

use Any::Moose;

extends 'Tatsumaki::Service';

use constant DEBUG => $ENV{TATSUMAKI_IRC_DEBUG};

use AnyEvent::IRC::Client;
use AnyEvent::IRC qw/mk_msg/;

use Carp ();
use HTTP::Request::Common;
use HTTP::Message::PSGI;
use namespace::clean -except => 'meta';

has post_path => (is => 'rw', isa => 'Str', default => '/_services/irc/chat' );
has server   => (is => 'rw', isa => 'Str');
has port     => (is => 'rw', isa => 'Str', default => 6667);
has nick     => (is => 'rw', isa => 'Str', default => 'LarryBird' );
has password => (is => 'rw', isa => 'Str', default => '');
has channels => (
    is => 'rw', isa => 'ArrayRef[Str]', default => sub { [ ] } 
);
has irc      => (is => 'rw', isa => 'AnyEvent::IRC::Client', lazy_build => 1);

around BUILDARGS => sub {
    my $orig  = shift;
    my $class = shift;

    if (@_ == 2) {
        $class->$orig(server => $_[0], password => $_[1]);
    } else {
        $class->$orig(@_);
    }
};

use Data::Dumper;
sub _build_irc {
    my $self = shift;
    my $irc = AnyEvent::IRC::Client->new(debug => DEBUG);

    $irc->reg_cb(
        error => sub { warn "ERROR: $_[1] ($_[2])\n"; warn Dumper($_[3])},
        connect    => sub { my ($con, $err) = @_; if ( $err ) { warn "Connection error: $err"; } },
        registered => sub { $self->registered(@_); },
        privatemsg => sub {
            $self->handle_message(@_);
        },
        publicmsg => sub {
            $self->handle_message(@_);
        },
        sent => sub {  },
        send => sub {  },
        debug_send => sub { $self->debug_send(@_); },

        channel_add    => sub { $self->channel_add(@_); },
        channel_remove => sub { $self->channel_remove(@_); },
        channel_change => sub { $self->channel_change(@_); },
        channel_nickmode_update => sub { $self->channel_nickmode_update(@_); },
        
        join => sub { $self->channel_join(@_) },
        part => sub { $self->channel_part(@_) },

        nick_change => sub { $self->nick_change(@_) },
    );
    return $irc;
}

sub debug_send { }

sub channel_add { }
sub channel_remove { }
sub channel_chhange { }
sub channel_nickmode_update { }
sub channel_join { }
sub channel_part { }
sub nick_change { }

sub registered {
    my ( $self, $con ) = @_;

    warn "[2] Registered on network";
    foreach my $channel ( @{ $self->channels } ) {
        $con->send_srv( JOIN => $channel );
    }
}

sub handle_message {
    my ( $self, $con, $from, $msg ) = @_;

    unless ( $msg->{command} eq 'PRIVMSG' ) {
        return;
    }

    # TODO refactor this (miyagawa says so)
    # This should probably use Tatsumaki::MessageQueue
    my $req = POST $self->post_path, [ 
        from => $msg->{prefix}, 
        to   => $msg->{params}->[0],
        body => $msg->{params}->[1]
    ];
    my $env = $req->to_psgi;

    $env->{'tatsumaki.irc'} = {
        client  => $con,
        message => $msg,
    };
    $env->{'psgi.streaming'} = 1;
    my $res = $self->application->($env);
    $res->(sub { my $res = shift }) if ref $res eq 'CODE';
}

sub start {
    my($self, $application) = @_;

    warn "[0] Connecting to " . $self->server . "\n";
    $self->irc->connect(
        $self->server, $self->port,
        { nick => $self->nick } 
    );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
