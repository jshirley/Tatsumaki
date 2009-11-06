package Tatsumaki::Application;
use AnyEvent;
use Moose;
use Tatsumaki::Handler;
use Tatsumaki::Request;
use Text::MicroTemplate::File;
use Try::Tiny;

use Plack::Middleware::Static;
use Tatsumaki::Middleware::BlockingFallback;

use overload q(&{}) => sub { shift->psgi_app }, fallback => 1;

has _rules => (is => 'rw', isa => 'ArrayRef');
has template => (is => 'rw', isa => 'Text::MicroTemplate::File', lazy_build => 1, handles => [ 'render_file' ]);

has static_path   => (is => 'rw', isa => 'Str', default => 'static');

around BUILDARGS => sub {
    my $orig = shift;
    my $class = shift;
    if (ref $_[0] eq 'ARRAY') {
        my $handlers = shift @_;
        my @rules;
        while (my($path, $handler) = splice @$handlers, 0, 2) {
            $path = qr/^$path/ unless ref $path eq 'RegExp';
            push @rules, { path => $path, handler => $handler };
        }
        $class->$orig(_rules => \@rules, @_);
    } else {
        $class->$orig(@_);
    }
};

sub route {
    my($self, $path, $handler) = @_;
    $path = qr/^$path/ unless ref $path eq 'RegExp';
    push @{$self->_rules}, { path => $path, handler => $handler };
}

sub dispatch {
    my($self, $path) = @_;

    for my $rule (@{$self->_rules}) {
        if ($path =~ $rule->{path}) {
            my $args = [ $1, $2, $3, $4, $5, $6, $7, $8, $9 ];
            return sub { $rule->{handler}->new(@_, args => $args) };
        }
    }

    return;
}

sub psgi_app {
    my $self = shift;
    return $self->{psgi_app} ||= $self->compile_psgi_app;
}

sub compile_psgi_app {
    my $self = shift;

    Scalar::Util::weaken($self);

    my $app = sub {
        my $env = shift;
        my $req = Tatsumaki::Request->new($env);

        my $handler = $self->dispatch($req->path)
            or return [ 404, [ 'Content-Type' => 'text/html' ], [ "404 Not Found" ] ];

        # TODO: if you throw exception from nonblocking callback, there seems no way to catch it
        my $res;
        try {
            $res = $handler->(
                application => $self,
                handler => $handler,
                request => $req,
            )->run;
        } catch {
            if ($_->isa('Tatsumaki::Error::HTTP')) {
                $res = [ $_->code, [ 'Content-Type' => 'text/plain' ], [ $_->message ] ];
            } else {
                warn $_;
                $res = [ 500, [ 'Content-Type' => 'text/plain' ], [ "Internal Server Error" ] ];
            }
        };

        return $res;
    };

    $app = Plack::Middleware::Static->wrap($app, path => sub { s/^\/static\/// }, root => $self->static_path);
    $app = Tatsumaki::Middleware::BlockingFallback->wrap($app);

    $app;
}

sub _build_template {
    my $self = shift;
    Text::MicroTemplate::File->new(
        include_path => [ 'templates' ],
        use_cache => 0,
    );
}

sub template_path {
    my $self = shift;
    if (@_) {
        my $path = ref $_[0] eq 'ARRAY' ? $_[0] : [ $_[0] ];
        $self->template->{include_path} = $path;
    }
    $self->template->{include_path};
}

1;


