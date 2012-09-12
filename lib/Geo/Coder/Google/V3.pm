package Geo::Coder::Google::V3;

use strict;
use warnings;
our $VERSION = '0.11_01';

use Carp;
use Encode;
use JSON;
use HTTP::Request;
use LWP::UserAgent;
use URI;

sub new {
    my($class, %param) = @_;

    my $host     = delete $param{host}     || 'maps.googleapis.com';

    my $language = delete $param{language} || delete $param{hl};
    my $region   = delete $param{region}   || delete $param{gl};
    my $oe       = delete $param{oe}       || 'utf8';
    my $sensor   = delete $param{sensor}   || 0;
    my $client   = delete $param{client}   || '';
    my $key      = delete $param{key}      || '';
   
    bless { 
        host => $host, language => $language,
        region => $region, oe => $oe, sensor => $sensor,
        client => $client, key => $key,
    }, $class;
}

sub ua {
    my $self    = shift;
    $self->{ua} = shift if @_;
    $self->{ua} = LWP::UserAgent->new(agent => __PACKAGE__ . "/$VERSION")
        unless defined $self->{ua};
    return $self->{ua};
}

sub geocode {
    my $self = shift;

    $self->{"last_res"}    = undef;
    $self->{"last_data"}   = undef;
    $self->{"last_status"} = undef;

    my %param;
    if (@_ % 2 == 0) {
        %param = @_;
    } else {
        $param{location} = shift;
    }

    my $location = $param{location} 
        or Carp::croak("Usage: geocode(location => \$location)");

    if (Encode::is_utf8($location)) {
        $location = Encode::encode_utf8($location);
    }

    my $uri = URI->new("http://$self->{host}/maps/api/geocode/json");
    my %query_parameters = (address => $location);
    $query_parameters{language} = $self->{language} if defined $self->{language};
    $query_parameters{region} = $self->{region} if defined $self->{region};
    $query_parameters{oe} = $self->{oe};
    $query_parameters{sensor} = $self->{sensor} ? 'true' : 'false';
    $uri->query_form(%query_parameters);
    my $url = $uri->as_string;

    # Process Maps Premier account info
    if ($self->{client} and $self->{key}) {
        $query_parameters{client} = $self->{client};
        $uri->query_form(%query_parameters);

        my $signature = $self->_make_signature($uri);
        # signature must be last parameter in query string or you get 403's
        $url = $uri->as_string;
        $url .= '&signature='.$signature if $signature;
    }

    $self->{"last_res"} = $self->ua->get($url);

    if ($self->{"last_res"}->is_error) {
        Carp::croak("Google Maps API returned error: " . $self->{"last_res"}->status_line);
    }

    $self->{"last_data"}   = $self->_json->decode($self->{"last_res"}->content);
    $self->{"last_status"} = $self->{"last_data"}->{"status"};

    my @results = @{ $self->{"last_data"}->{results} || [] };
    wantarray ? @results : $results[0];
}

sub _json {
    my $self=shift;
    $self->{"json"}=JSON->new->utf8
        unless defined $self->{"json"};
    return $self->{"json"};
}

# methods below adapted from 
# http://gmaps-samples.googlecode.com/svn/trunk/urlsigning/urlsigner.pl
sub _decode_urlsafe_base64 {
  my ($self, $content) = @_;

  $content =~ tr/-/\+/;
  $content =~ tr/_/\//;

  return MIME::Base64::decode_base64($content);
}

sub _encode_urlsafe{
  my ($self, $content) = @_;
  $content =~ tr/\+/\-/;
  $content =~ tr/\//\_/;

  return $content;
}

sub _make_signature {
  my ($self, $uri) = @_;

  require Digest::HMAC_SHA1;
  require MIME::Base64;

  my $key = $self->_decode_urlsafe_base64($self->{key});
  my $to_sign = $uri->path_query;

  my $digest = Digest::HMAC_SHA1->new($key);
  $digest->add($to_sign);
  my $signature = $digest->b64digest;

  return $self->_encode_urlsafe($signature);
}


1;
__END__

=head1 NAME

Geo::Coder::Google::V3 - Google Maps Geocoding API V3

=head1 SYNOPSIS

  use Geo::Coder::Google;

  my $geocoder = Geo::Coder::Google->new(apiver => 3);
  my $location = $geocoder->geocode( location => 'Hollywood and Highland, Los Angeles, CA' );

=head1 DESCRIPTION

Geo::Coder::Google::V3 provides a geocoding functionality using Google Maps API V3.

=head1 METHODS

=head2 new

  $geocoder = Geo::Coder::Google->new(apiver => 3);
  $geocoder = Geo::Coder::Google->new(apiver => 3, language => 'ru');
  $geocoder = Geo::Coder::Google->new(apiver => 3, gl => 'ca');
  $geocoder = Geo::Coder::Google->new(apiver => 3, oe => 'latin1');

To specify the language of Google's response add C<language> parameter
with a two-letter value. Note that adding that parameter does not
guarantee that every request returns translated data.

You can also set C<gl> parameter to set country code (e.g. I<ca> for Canada).

You can ask for a character encoding other than utf-8 by setting the I<oe>
parameter, but this is not recommended.

You can optionally use your Maps Premier Client ID, by passing your client
code as the C<client> parameter and your private key as the C<key> parameter.
The URL signing for Premier Client IDs requires the I<Digest::HMAC_SHA1>
and I<MIME::Base64> modules. To test your client, set the environment
variables GMAP_CLIENT and GMAP_KEY before running 02_v3_live.t

  GMAP_CLIENT=your_id GMAP_KEY='your_key' make test

=head2 geocode

  $location = $geocoder->geocode(location => $location);
  @location = $geocoder->geocode(location => $location);

Queries I<$location> to Google Maps geocoding API and returns hash
reference returned back from API server. When you cann the method in
an array context, it returns all the candidates got back, while it
returns the 1st one in a scalar context.

When you'd like to pass non-ascii string as a location, you should
pass it as either UTF-8 bytes or Unicode flagged string.

=head2 ua

Accessor method to get and set UserAgent object used internally. You
can call I<env_proxy> for example, to get the proxy information from
environment variables:

  $coder->ua->env_proxy;

You can also set your own User-Agent object:

  $coder->ua( LWPx::ParanoidAgent->new );

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Geo::Coder::Yahoo>, L<http://www.google.com/apis/maps/documentation/#Geocoding_Examples>

List of supported languages: L<http://spreadsheets.google.com/pub?key=p9pdwsai2hDMsLkXsoM05KQ&gid=1>

=cut
