#!/usr/bin/perl

use warnings;
use strict;

package Device::TotalConnectComfort;

use Carp;
use Data::Dumper;
use File::Slurp;
use JSON;
use LWP::UserAgent;

use base qw( Exporter );
our @EXPORT_OK = qw( new );

my $DEBUG = 1;
$\ = "\n";

# Make the auth token globally accessible
my $auth_token;

# Requests:
#   .../Session : Login to service, get user detains
#   .../locations?userId=377023&allData=True : Get data on all thermostats. If you have multiple locations, you use this to get data on them all.
#   .../gateways?locationId=364809&allData=False : get data on base station/gateway
#   .../evoTouchSystems?locationId=364809&allData=True : return all data for a location

sub new {
    shift;
    my $username = shift || croak "No username supplied";
    my $password = shift || croak "No password supplied";
    my $app_id   = shift || croak "No application id supplied";
    my $is_test  = shift || 0;

    my $test_file = 't/login_response';
    my $response_body;

    if ($is_test) {
        print "Using cached response" if $DEBUG;

        open( my $test_file_fh, '<', $test_file )
          or die "Unable to open test input file";
        $response_body = read_file($test_file_fh);
    }
    else {
        print "Actually logging in" if $DEBUG;

        my $r = do_login( $username, $password, $app_id );

        open( my $response_fh, '>', $test_file )
          or die "Unable to open file for writing: $!";
        $response_body = $r->content;
        print $response_fh $response_body;
    }

    my $login_response = from_json($response_body);
    die "Server response did not contain a session id token"
      unless $login_response->{sessionId};

    my $self;
    $self->{sessionId} = $login_response->{sessionId};
    $self->{username}  = $login_response->{userInfo}->{username};
    $self->{userID}    = $login_response->{userInfo}->{userID};

    # include a valid_until counter - unsure how long sessions are valid for

    # store auth token
    $auth_token = $self->{sessionId};

    bless $self;
}

# Perform login to API and retrieve sessionId
sub do_login {
    my %login_params;
    $login_params{Username}      = shift || croak "No username supplied";
    $login_params{Password}      = shift || croak "No password supplied";
    $login_params{ApplicationId} = shift || croak "No application id supplied";

    my ( $ua, $request ) = _setup_request(
        method => 'POST',
        path   => 'Session',
        body   => to_json( \%login_params ),
    );

    my $r = $ua->request($request);

    die "Invalid username/password" if $r->code == '401';
    die "App id is incorrect"       if $r->code == '400';
    die "Unknown error occurred: ", $r->code if $r->code != '200';

    return $r;
}

# Creates a LWP::UserAgent request with the correct headers
sub _setup_request {
    my %params = @_;
    # method, path, url_params (url parameters), body (body content)

    # Setup location
    my $host      = 'https://rs.alarmnet.com';
    my $base_path = '/TotalConnectComfort/WebAPI/api/';
    my $url       = URI->new( $host . $base_path . $params{path} );
    $url->query_form($params{url_params}) if $params{url_params};

    # Add useragent string
    my $ua = LWP::UserAgent->new;
    $ua->agent('User-Agent: RestSharp 104.1.0.0');

    my $request = HTTP::Request->new( $params{method} => $url );
    $request->header( 'Content-Type' => 'application/json' );
    $request->header( 'sessionId' => $auth_token ) if $auth_token;
    $request->content( $params{body} ) if $params{body};

    return ( $ua, $request );
}

# Actually make the request, handle errors and return JSON-decoded body
sub _handle_request {
    my $ua = shift;
    my $request = shift;
    my $debug = shift;

    my $r = $ua->request($request);

    die "Invalid username/password, or session timed out" if $r->code == '401';
    die "App id is incorrect (or similar error)" if $r->code == '400';
    die "Unknown error occurred: ", $r->code if $r->code != '200';

    my $response_body = $r->content;

    return from_json($response_body);
}

# Put setup and requesting together
# API parameters in, JSON out.
sub _api_call {
    my %params = @_;

    # Setup request
    my ($ua, $request) = _setup_request(%params);

    print "Making request:\n", $request->as_string if $params{debug};

    # Make request, return JSON
    return _handle_request($ua, $request);
}

# Get data on all thermostats. If you have multiple locations, you use this to get data on them all.
sub get_locations {
    my $self = shift;

    my $location_data = _api_call(
        method => 'GET',
        path   => 'locations',
        url_params => { userId => $self->{userID}, allData => 'True', }, # consistent casing, say what?
        debug => 'true',
    );

}

1;
