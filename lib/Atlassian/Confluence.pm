package Atlassian::Confluence;
use warnings;
use strict;

=head1 NAME

Atlassian::Confluence 

=head1 VERSION

Version 1.0

=cut

our $VERSION = '1.0';

=head1 SYNOPSIS

This module provides an XML-RPC interface to Atlassian Confluence wikis. 

  use Atlassian::Confluence;

  my $wiki = Atlassian::Confluence->new("http://http://wiki.domain.com/rpc/xmlrpc", 
                                        $user, $pass);
  $wiki->encoding('iso-8859-1');

  my @pages = $wiki->getPages('spacekey');

This module will correctly dispatch XML-RPC calls listed in the Atlassian Confluence Remote API Specification for Confluence 3.x, revision date Mar 11 2010. All calls which have arguments other than strings have wrapper methods which deal with argument conversion.  

See http://confluence.atlassian.com/display/DOC/Remote+API+Specification for more details on using the remote API.

=head1 XML-RPC DATA TYPES

=head1 METHODS

new(URI [, username, password] [,api-version])
login(URI [, username, password] [,api-version])

Create an Atlassian::Confluence object. If the target wiki permits anonymous access to its XML-RPC interface, no login information is required.  Use api-version only if Confluence introduces a new API. Currently there is only one ('confluence1').
If the connection fails for any reason (local or remote), no object is created.

encoding(encoding)

Set the XML encoding for the remote conversation. The default is utf-8, in line with the Confluence default. You should set this to match the value configured in the target wiki server. 

=head1 SUPPORT

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Atlassian-Confluence>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Atlassian-Confluence>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Atlassian-Confluence>

=item * Search CPAN

L<http://search.cpan.org/dist/Atlassian-Confluence/>

=back

=head1 ACKNOWLEDGEMENTS

Asgeir.Nilsen@telenor.com wrote a simple module for the Atlassian Confluence wiki which inspired this one.

=head1 COPYRIGHT & LICENSE

Copyright 2009,2010 Sue Spence, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

use RPC::XML;
use RPC::XML::Client;
use File::Basename;
use Carp;
use Scalar::Util "looks_like_number";
use fields qw(token url client error encoding api_version );
use Data::Dumper;

use constant CONFLUENCE_API_DEFAULT => 'confluence1';

# Set the default RPC::XML encoding. The RPC::XML module defaults to us-ascii. 
# Confluence as shipped defaults to UTF-8, so it is more appropriate for this module 
# to set it to UTF-8. 
# Users can change the encoding via the encoding method.
$RPC::XML::ENCODING = "utf-8";

# Import CONF_TRACE environment variable. If this is set, the module will emit 
# debugging information
use Env qw(CONF_TRACE);

# Global variables
our $AUTOLOAD;

sub new {
  my ($self, $url, $user, $pass, $api) = @_;
  unless (ref $self) {
    $self = fields::new($self);
  }
  $self->{url} = $url;
  if ($api) {
    carp "Setting API version to $api" if $CONF_TRACE;
    $self->{api_version} = $api;
  } else {
    $self->{api_version} = CONFLUENCE_API_DEFAULT;
  }
  carp "Creating client connection to $url" if $CONF_TRACE;
  $self->{client} = RPC::XML::Client->new($url, 'useragent', [('timeout',600)] );
  if ($user) {
    carp "Logging in $user" if $CONF_TRACE;
    my $res = $self->{client}->simple_request($self->{api_version} . ".login", $user, $pass);
    # if $res is a hash, there was an error on the remote side (confluence)
    if (defined $res) { 
      if (ref($res) eq 'HASH') {
        carp "Failed to connect to wiki: $res->{faultString}" if $CONF_TRACE;
        return;
      } else {
        $self->{token} = $res;
      }
    } else {
      carp "Failed to connect to wiki: $RPC::XML::ERROR" if $CONF_TRACE;
      return; 
    }
  } else {
    carp "No login credentials provided, attempting anonymous access" if $CONF_TRACE;
    $self->{token} = '';
  }
  return $self;
}

# login is a synonym for new
sub login {
  return new(@_);
}

sub logout {
  my ($self) = @_;
  if ($self->{token}) {
    my $res = _do_rpc_request($self, "logout");
    return $res;
  } else {
    # No token, so not logged in. Return false.
    return 0;
  }
}

# Set the XML encoding value.
sub encoding {
  my ($self, $enc) = @_;
  if ($enc) {
    carp "Setting xml encoding to $enc";
    $RPC::XML::ENCODING = $enc;
  }
}

sub api_version{
  my ($self, $api) = @_;
  if ($api) {
    carp "Setting Confluence API to $api" if $CONF_TRACE;
    $self->{api_version} = $api;
  }
  return $self->{api_version};
}

############################################################
#  XML-RPC datatype conversions
#  Basic types: string, integer, long, boolean, base64

sub integer {
  my $val;
  if (ref $_[0] eq __PACKAGE__) { $val = $_[1]; } 
  else { $val = $_[0]; }
  return RPC::XML::int->new($val);
}

sub long {
  my $val;
  if (ref $_[0] eq __PACKAGE__) { $val = $_[1]; } 
  else { $val = $_[0]; }
  return RPC::XML::string->new($val);
}

sub boolean {
  my $val;
  if (ref $_[0] eq __PACKAGE__) { $val = $_[1]; } 
  else { $val = $_[0]; }
  return RPC::XML::boolean->new($val);
}

sub string {
  my $val;
  if (ref $_[0] eq __PACKAGE__) { $val = $_[1]; } 
  else { $val = $_[0]; }
  warn "String: $val" if $CONF_TRACE;
  return RPC::XML::string->new($val);
}

sub base64 {
  my $val;
  if (ref $_[0] eq __PACKAGE__) { $val = $_[1]; } 
  else { $val = $_[0]; }
  warn "Base64 value - " . length($val) . " bytes" if $CONF_TRACE;
  return RPC::XML::base64->new($val);
}
 
# Confluence data objects 
sub space {
  my $val;
  if (ref $_[0] eq __PACKAGE__) { $val = $_[1]; }
  else { $val = $_[0]; }
  warn "Space struct" if $CONF_TRACE;
  if (ref $val eq 'HASH') {
    for my $field (keys %$val) {
      $val->{$field} = RPC::XML::string->new($val->{field});
    }
  } else {
    warn "Passed a non-hash to the space method" if $CONF_TRACE;
  }
}

sub page {
  my $val;
  if (ref $_[0] eq __PACKAGE__) { $val = $_[1]; } 
  else { $val = $_[0]; }
  warn "Page struct" if $CONF_TRACE;
  if (ref $val eq 'HASH') {
    for my $field (keys %$val) {
      if ($field eq 'version' || $field eq 'locks') {
        $val->{$field} = RPC::XML::int->new($val->{$field}); 
      } elsif ($field eq 'current' || $field eq 'homePage') {
        $val->{$field} = RPC::XML::boolean->new($val->{$field}); 
      } else {
        $val->{$field} = RPC::XML::string->new($val->{$field}); 
      }
    }
    return RPC::XML::struct->new($val);
  } else {
    warn "Passed a non-hash to the page method" if $CONF_TRACE;
  }
}

sub attachment {
  my $val;
  if (ref $_[0] eq __PACKAGE__) { $val = $_[1]; } 
  else { $val = $_[0]; }
  warn "Attachment struct" if $CONF_TRACE;
  if (ref $val eq 'HASH') {
    for my $field (keys %$val) {
      warn "Field is $field";
      $val->{$field} = RPC::XML::string->new($val->{$field}); 
    }
    return RPC::XML::struct->new($val);
  } else {
    warn "Passed a non-hash to the attachment method" if $CONF_TRACE;
  }
}

#  Space methods

sub addSpace {
  my ($self, $space) = @_;
  carp "addSpace" if $CONF_TRACE;
  my $res = _do_rpc_request($self, "addSpace", space($self, $space));
  return $res;
}

sub convertToPersonalSpace {
  my ($self, $userName, $spaceKey, $newSpaceName, $updateLinks) = @_;
  carp "convertToPersonalSpace" if $CONF_TRACE;
  my $res = _do_rpc_request($self, "convertToPersonalSpace", string($userName), string($spaceKey),
                            string($newSpaceName), boolean($updateLinks));
  return $res;
}

sub storeSpace {
  my ($self, $space) = @_;
  carp "storeSpace" if $CONF_TRACE;
  my $res = _do_rpc_request($self, "storeSpace", space($space));
  return $res;
}

sub importSpace {
  # $spaceDataFile must be the name of a zipped Confluence data file
  my ($self, $spaceDataFile) = @_;
  carp "importSpace" if $CONF_TRACE;
  my $ifh;
  if ($spaceDataFile) {
    open $ifh, "< $spaceDataFile" or 
      croak "Fatal: Failed to open $spaceDataFile, $!";
  } else {
    croak "Fatal: You must specify a file name"; 
  }
  binmode $ifh;
  my $filecontents;
  { local $/; $filecontents = <$ifh>; close $ifh; }
  my $res = _do_rpc_request($self, "importSpace", base64($filecontents));
  return $res;
}

# File attachment methods

sub addAttachment {
  my ($self, $contentId, $attachmentFile, $comment) = @_;
  my $ifh;
  if ($attachmentFile) {
    open $ifh, "< $attachmentFile" or 
      croak "Fatal: Failed to open $attachmentFile, $!";
  } else {
    croak "Fatal: You must specify a file name"; 
  }
  croak "Fatal: You must supply a content ID" unless $contentId;
  $comment = "Uploaded via the Atlassian::Confluence module (http://search.cpan.org/~sue/)" unless $comment;
  binmode $ifh;
  my $filecontents;
  { local $/; $filecontents = <$ifh>; close $ifh; }
  my $filename = basename $attachmentFile;
  my $attachment = { fileName => $filename,
                     contentType => "application/octet-stream",
                     comment => $comment,
                   };
  my $res = _do_rpc_request($self, "addAttachment", string($contentId), 
                            attachment($attachment), base64($filecontents));
  return $res;
}

# ADMINISTRATION METHODS

sub exportSite {
  my ($self, $exportAttachments) = @_;
  carp "exportSite: exportAttachments  $exportAttachments" if $CONF_TRACE;
  my $res = _do_rpc_request($self, "exportSite", boolean($exportAttachments));
  return $res;
}

sub getClusterInformation {
  my ($self) = @_;
  carp "getClusterInformation" if $CONF_TRACE;
  my $res = _do_rpc_request($self, "getClusterInformation");
  return $res;
}

sub getClusterNodeStatuses {
  my ($self) = @_;
  carp "getClusterNodeStatuses" if $CONF_TRACE;
  my $res = _do_rpc_request($self, "getClusterNodeStatuses");
  return $res;
}

sub isPluginEnabled {
  my ($self, $pluginKey) = @_;
  carp "isPluginEnabled: pluginKey $pluginKey" if $CONF_TRACE;
  my $res = _do_rpc_request($self, "isPluginEnabled", string($pluginKey));
  return $res;
}

sub installPlugin {
  my ($self, $pluginFileName) = @_;
  my $ifh;
  if ($pluginFileName) {
    open $ifh, "< $pluginFileName" or 
      croak "Fatal: Failed to open $pluginFileName, $!";
  } else {
    croak "Fatal: You must specify a file name"; 
  }
  binmode $ifh;
  my $filecontents;
  { local $/; $filecontents = <$ifh>; close $ifh; }
  my $filename = basename $pluginFileName;
  my $res = _do_rpc_request($self, "addAttachment", 
                            string($filename), base64($filecontents));
  return $res;
}

# GENERAL

sub getServerInfo {
  my ($self) = @_;
  carp "getServerInfo: no args" if $CONF_TRACE;
  my $res = _do_rpc_request($self, "getServerInfo");
  return $res;
}

# PAGES

sub getPage {
  my ($self, $pageId) = @_;
  carp "getPage" if $CONF_TRACE;
  my $res = _do_rpc_request($self, "getPage", string($pageId));
  return $res;
}
sub getPageHistory {
  my ($self, $pageId) = @_;
  carp "getPageHistory" if $CONF_TRACE;
  my $res = _do_rpc_request($self, "getPageHistory", string($pageId));
  return $res;
}

# Page storePage(String token, Page page) - add or update a page. 
sub storePage {
  my ($self, $page) = @_;
  carp "storePage" if $CONF_TRACE;
  my $res = _do_rpc_request($self, "storePage", page($self, $page));
  return $res;
}

sub _do_rpc_request {
  my ($self, $method, @args) = @_;
  carp "Method: $method  @args" if $CONF_TRACE;
  my $res = $self->{client}->simple_request($self->{api_version} . "." . $method, $self->{token}, @args);
  carp "Result = $res"  if $CONF_TRACE;
  if (defined $res) { 
    if (ref $res eq 'HASH' && $res->{faultString}) {
      warn "ERROR: ", $res->{faultString} if $CONF_TRACE;
      return $res->{faultString};
    }
  } else {
    warn "ERROR: ", $RPC::XML::ERROR if $CONF_TRACE;
    return $RPC::XML::ERROR;
  }
  return $res;
}

#  
sub AUTOLOAD {
  my $self = shift;
  # $AUTOLOAD is "Atlassian::Confluence::remote_method". Remove "Atlassian::Confluence::" so
  # the name can be used in the RPC call to the wiki site.
  $AUTOLOAD =~ s/^.*:://;  
  return if $AUTOLOAD =~ /DESTROY/;
  warn "Autoloading $AUTOLOAD" if $CONF_TRACE;
  my @args = map { string($_) } @_;
  my $res = _do_rpc_request($self, $AUTOLOAD, @args);
  return $res;
}

1; # End of Atlassian::Confluence
