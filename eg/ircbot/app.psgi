#!/usr/bin/perl
use strict;
use warnings;
use Tatsumaki::Error;
use Tatsumaki::Application;
use Tatsumaki::HTTPClient;
use JSON;

use lib 'lib';

package IRCHandler;
use base qw(Tatsumaki::Handler::IRC);
__PACKAGE__->asynchronous(1);

use JSON;
use URI;

sub post {
    my $self = shift;

    my $message = $self->irc_message;

    my $uri = URI->new("http://ajax.googleapis.com/ajax/services/language/translate");
    $uri->query_form(v => "1.0", langpair => "en|ja", q => $message->body);

    my $client = Tatsumaki::HTTPClient->new;
    $client->get($uri, $self->async_cb(sub { $self->on_response($message, @_) }));
}

sub on_response {
    my($self, $message, $res) = @_;
    my $result = JSON::decode_json($res->content);
    my $text   = $result->{responseData}{translatedText};

    utf8::encode($text) if utf8::is_utf8($text);
    $message->reply($text);
    #$message->reply("I hate you all and I want to die");
    $self->finish;
}

package main;
use Tatsumaki::Service::IRC;

my $svc = Tatsumaki::Service::IRC->new(
    $ENV{IRC_SERVER}, $ENV{IRC_PASSWORD} || '',
);
$svc->channels([ '#chc' ]);

my $app = Tatsumaki::Application->new([
    '/_services/irc/chat' => 'IRCHandler',
]);

$app->add_service($svc);
$app;
