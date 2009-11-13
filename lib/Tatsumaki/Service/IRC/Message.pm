package Tatsumaki::Service::IRC::Message;
use Moose;

has conn => (is => 'ro', isa => 'AnyEvent::IRC::Client', required => 1);
has from => (is => 'rw', isa => 'Str');
has to   => (is => 'rw', isa => 'Str');
has body => (is => 'rw', isa => 'Str');
has command => (is => 'rw', isa => 'Str');
has arg  => (is => 'rw', isa => 'Str');

has message => (is => 'ro', isa => 'HashRef');

sub reply {
    my $self = shift;
    my($body) = @_;

    my $reply = $self->make_reply;
    $reply->body($body);
    $reply->send;
}

sub make_reply {
    my ( $self ) = @_;

    __PACKAGE__->new(
        to   => $self->to,
        from => $self->to,
        conn => $self->conn
    );
}

sub send {
    my ( $self ) = @_;
    $self->conn->send_srv( PRIVMSG => $self->to, $self->body );
}

1;
