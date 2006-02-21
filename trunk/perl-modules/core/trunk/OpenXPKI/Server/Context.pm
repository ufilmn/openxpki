# OpenXPKI Server Context Singleton
# Written by Martin Bartosch for the OpenXPKI project 2005
# Copyright (c) 2005 by The OpenXPKI Project
# $Revision$

package OpenXPKI::Server::Context;

use strict;
use base qw( Exporter );

our @EXPORT_OK = qw( CTX );

#use Smart::Comments;

use OpenXPKI::Server::Init;
use OpenXPKI::Exception;

my $context = {
    initialized => 0,

    exported => {
	# always created by this package
	xml_config   => undef,
	crypto_layer => undef,
	pki_realm    => undef,
	log          => undef,
	dbi_backend  => undef,
	dbi_workflow => undef,

	# user-settable
	api          => undef,
	server       => undef,
        gui          => undef,
        acl          => undef,
        session      => undef,
        debug        => undef,
    },
};



# only called statically
sub CTX {
    my @objects = @_;
    
    if (! $context->{initialized}) {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_SERVER_CONTEXT_CTX_NOT_INITIALIZED",
	    );
    }

    # TODO: add access control? (idea: limit access to this method to
    # authorized parts of the code only, explicity excluding interface
    # implementations...)

    my @return;
    foreach my $object (@objects) {
	
	if (! exists $context->{exported}->{$object}) {
	    OpenXPKI::Exception->throw (
		message => "I18N_OPENXPKI_SERVER_CONTEXT_CTX_OBJECT_NOT_FOUND",
                params  => {OBJECT => $object},
		);
	}
	push @return, $context->{exported}->{$object};
    }

    if (wantarray) {
	return @return;
    } else {
	if (scalar @return) {
	    return $return[0];
	} else {
	    return;
	}
    }
}


# only called statically (and is only executed ONCE)
sub create {
    my $params = { @_ };

    if ($context->{initialized}) {
	return 1;
    }
    
    ### instantiating Init...
    my $init = OpenXPKI::Server::Init->new(DEBUG => $params->{DEBUG});

    ### getting xml config...
    my $xml_config = $init->get_xml_config(CONFIG => $params->{"CONFIG"});
    $init->init_i18n(CONFIG => $xml_config);

    ### getting crypto layer...
    my $crypto_layer = $init->get_crypto_layer(CONFIG => $xml_config);

    ### getting pki_realm...
    my $pki_realm    = $init->get_pki_realms(CONFIG => $xml_config,
					     CRYPTO => $crypto_layer);

    ### getting logger...
    my $log          = $init->get_log(CONFIG => $xml_config);

    ### getting backend database...
    my $dbi_backend  = $init->get_dbi(CONFIG => $xml_config,
				      LOG    => $log);

    ### getting workflow database...
    my $dbi_workflow = $init->get_dbi(CONFIG => $xml_config,
				      LOG    => $log);


    ### record these for later use...
    setcontext(xml_config     => $xml_config,
	       crypto_layer   => $crypto_layer,
	       pki_realm      => $pki_realm,
	       log            => $log,
	       dbi_backend    => $dbi_backend,
	       dbi_workflow   => $dbi_workflow,
               debug          => $params->{DEBUG},
	);

    $context->{initialized} = 1;

    return 1;
}


# add new entries to the context
sub setcontext {
    my $params = { @_ };
    
    foreach my $key (keys %{$params}) {
	### setting $key in context...
	if (! exists $context->{exported}->{$key} ) {
	    ### unknown key...
	    OpenXPKI::Exception->throw (
		message => "I18N_OPENXPKI_SERVER_CONTEXT_SETCONTEXT_ILLEGAL_ENTRY",
		);
	}

	### already defined?
	if (defined ($context->{exported}->{$key})) {
	    ### yes, bail out
	    OpenXPKI::Exception->throw (
		message => "I18N_OPENXPKI_SERVER_CONTEXT_SETCONTEXT_ALREADY_DEFINED",
		);
	}

	### setting internal state...
	$context->{exported}->{$key} = $params->{$key};
    }

    return 1;
}

1;
__END__

=head1 Description

This package provices a globally accessible Context singleton that holds
object references for the OpenXPKI base infrastructure.
Typically the package is included in every module that needs to access
basic functions such as logging or database operations.

During startup of the system this Context package must be initialized 
once by passing in the configuration file (see create()).
After initialization has completed the package holds a global context
that can be accessed from anywhere within the OpenXPKI code structure.

Callers typically use the CTX() function to access this context. See
below for usage hints.

=head2 Basic objects (always available)

The following Context objects are always created and can be retrieved
by calling CTX('...') once create() has been called:

=over

=item * xml_config

=item * crypto_layer

=item * pki_realm

=item * log

=item * dbi_backend

=item * dbi_workflow

=back

=head2 Auxiliary objects (only available after explicit addition)

In addition to the above objects that are guaranteed to exist after
initialization has happened, the following can be retrieved if they
have been explicitly added to the Context after initialization
via setcontext().

=over

=item *	api

=item * server

=back

These objects are usually created and attached by the OpenXPKI Server
initialization procedure in order to make the objects available globally.


=head1 Functions

=head2 CTX($)

Allows to retrieve an object reference for the specified name. 
If called before initialization has happened (see create() function) 
calling CTX() yields an exception.
CTX() returns the associated object in the global context.

Usage:

  use OpenXPKI::Server::Context;
  my $config = OpenXPKI::Server::Context::CTX('xml_config');

or simpler:

  use OpenXPKI::Server::Context qw( CTX );
  my $config = CTX('xml_config');

=head2 CTX(@)

It is also possible to call CTX() in array context to obtain multiple
context entries at once:

  my ($config, $log, $dbi) = CTX('xml_config', 'log', 'dbi_backend');


=head2 create(%)

Initialization must be done ONCE by the server process.
Expects the XML configuration file via the named parameter CONFIG.
The named parameter DEBUG may be set to a true value to enable debugging.

Usage:

  use OpenXPKI::Server::Context;

  OpenXPKI::Server::Context::create(
         CONFIG => 't/config.xml',
         DEBUG => 0,
     ));


=head2 setcontext(%)

Allows to set additional globally available Context information after
the Context has been initialized via create().

To prevent abuse (storing arbitrary stuff globally) the Context module
only allows to set Context entries that are allowed explicitly. 
Only the keys mentioned above are accepted, trying to set an unsupported
Context object yields an exception.

Please note that it is NOT possible to overwrite a Context object
once it has been set once. setcontext() will throw an exception if
somebody tries to set an object that has already been attached.

Usage:

  # attach this server object and the API to the global context
  OpenXPKI::Server::Context::setcontext(
    server => $self,
    api    => OpenXPKI::Server::API->new(DEBUG => $self->{DEBUG}),
  );


