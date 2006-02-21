## OpenXPKI::Server::ACL.pm 
##
## Written by Michael Bell 2006
## Copyright (C) 2006 by The OpenXPKI Project
## $Revision: 148 $

use strict;
use warnings;
use utf8;

package OpenXPKI::Server::ACL;

use English;
use OpenXPKI qw(debug);
use OpenXPKI::Exception;
use OpenXPKI::Server::Context qw( CTX );

## constructor and destructor stuff

sub new {
    my $that = shift;
    my $class = ref($that) || $that;

    my $self = {
                DEBUG     => CTX('debug'),
               };

    bless $self, $class;

    my $keys = { @_ };
    $self->{DEBUG}       = 1 if ($keys->{DEBUG});
    $self->debug ("start");

    return undef if (not $self->__load_config ());

    $self->debug ("end");
    return $self;
}

#############################################################################
##                         load the configuration                          ##
##                            (caching support)                            ##
#############################################################################

sub __load_config
{
    my $self = shift;
    $self->debug ("start");

    ## load all PKI realms

    my $realms = CTX('xml_config')->get_xpath_count (XPATH => 'pki_realm');
    for (my $i=0; $i < $realms; $i++)
    {
        $self->__load_pki_realm ({PKI_REALM => $i});
    }

    $self->debug ("leaving function successfully");
    return 1;
}

sub __load_pki_realm
{
    my $self  = shift;
    my $keys  = shift;
    my $realm = $keys->{PKI_REALM};

    my $name = CTX('xml_config')->get_xpath (XPATH   => ['pki_realm', 'name'],
                                         COUNTER => [$realm, 0]);
    $self->{PKI_REALM}->{$name}->{POS} = $realm;

    $self->__load_server      ({PKI_REALM => $name});
    $self->__load_roles       ({PKI_REALM => $name});
    $self->__load_permissions ({PKI_REALM => $name});

    return 1;
}

sub __load_server
{
    my $self  = shift;
    my $keys  = shift;
    my $realm = $keys->{PKI_REALM};
    my $pkiid = $self->{PKI_REALM}->{$realm}->{POS};

    $self->{SERVER_ID} = CTX('xml_config')->get_xpath (
                             XPATH   => ['common', 'database', 'server_id'],
                             COUNTER => [0, 0, 0]);
    my $servers = CTX('xml_config')->get_xpath_count (
                      XPATH   => ['pki_realm', 'acl', 'server'],
                      COUNTER => [$pkiid, 0]);
    for (my $i=0; $i < $servers; $i++)
    {
        my $value = CTX('xml_config')->get_xpath (
                       XPATH   => ['pki_realm', 'acl', 'server', 'id'],
                       COUNTER => [ $pkiid, 0, $i, 0]);
        my $name = CTX('xml_config')->get_xpath (
                       XPATH   => ['pki_realm', 'acl', 'server', 'name'],
                       COUNTER => [ $pkiid, 0, $i, 0]);
        if ($value == $self->{SERVER_ID})
        {
            $self->{SERVER_NAME} = $name;
            last;
        }
    }
    return 1;
}

sub __load_roles
{
    my $self  = shift;
    my $keys  = shift;
    my $realm = $keys->{PKI_REALM};
    my $pkiid = $self->{PKI_REALM}->{$realm}->{POS};

    my $roles = CTX('xml_config')->get_xpath_count (
                      XPATH   => ['pki_realm', 'acl', 'role'],
                      COUNTER => [$pkiid, 0]);
    for (my $i=0; $i < $roles; $i++)
    {
        my $role = CTX('xml_config')->get_xpath (
                       XPATH   => ['pki_realm', 'acl', 'role'],
                       COUNTER => [ $pkiid, 0, $i]);
        if ($i != 0)
        {
            push @{$self->{PKI_REALM}->{$realm}->{ROLES}}, $role;
        } else {
            $self->{PKI_REALM}->{$realm}->{ROLES} = [ $role ];
        }
    }
    return 1;
}

sub __load_permissions
{
    my $self  = shift;
    my $keys  = shift;
    my $realm = $keys->{PKI_REALM};
    my $pkiid = $self->{PKI_REALM}->{$realm}->{POS};

    my $perms = CTX('xml_config')->get_xpath_count (
                      XPATH   => ['pki_realm', 'acl', 'permission'],
                      COUNTER => [$pkiid, 0]);
    for (my $i=0; $i < $perms; $i++)
    {
        my $server = CTX('xml_config')->get_xpath (
                       XPATH   => ['pki_realm', 'acl', 'permission', 'server'],
                       COUNTER => [ $pkiid, 0, $i]);
        my $activity = CTX('xml_config')->get_xpath (
                       XPATH   => ['pki_realm', 'acl', 'permission', 'activity'],
                       COUNTER => [ $pkiid, 0, $i]);
        my $owner = CTX('xml_config')->get_xpath (
                       XPATH   => ['pki_realm', 'acl', 'permission', 'affected_role'],
                       COUNTER => [ $pkiid, 0, $i]);
        my $user = CTX('xml_config')->get_xpath (
                       XPATH   => ['pki_realm', 'acl', 'permission', 'auth_role'],
                       COUNTER => [ $pkiid, 0, $i]);

        my @perms = ();

        ## evaluate server
        if ($server ne "*" and
            $server ne $self->{SERVER_NAME})
        {
            ## we only need the permissions for this server
            ## this reduces the propabilities of hash collisions
            next;
        }

        ## evaluate owner
        my @owners = ($owner);
           @owners = @{$self->{PKI_REALM}->{$realm}->{ROLES}}
               if ($owner eq "*");

        ## evaluate user
        my @users = ($user);
           @users = @{$self->{PKI_REALM}->{$realm}->{ROLES}}
               if ($user eq "*");

        ## an activity wildcard results in a *
        ## so we must check always for the activity and *
        ## before we throw an exception

        foreach $owner (@owners)
        {
            foreach $user (@users)
            {
                if (exists $self->{PKI_REALM}->{$realm}->{ACL}->{$owner}->{$user})
                {
                    push @{$self->{PKI_REALM}->{$realm}->{ACL}->{$owner}->{$user}},
                         $activity;
                } else {
                    $self->{PKI_REALM}->{$realm}->{ACL}->{$owner}->{$user} =
                        [ $activity ];
                }
                $self->debug ("permission: $realm, $owner, $user, $activity");
            }
        }
    }
    return 1;
}

########################################################################
##                          identify the user                         ##
########################################################################

sub authorize
{
    my $self = shift;
    my $keys = shift;

    ## we need the following things:
    ##     - PKI realm
    ##     - auth_role
    ##     - affected_role
    ##     - activity

    my $realm    = CTX('session')->get_pki_realm();
    my $user     = CTX('session')->get_role();
    my $owner    = "Anonymous";
       $owner    = $keys->{AFFECTED_ROLE} if (exists $keys->{AFFECTED_ROLE} and
                                              defined $keys->{AFFECTED_ROLE});
    my $activity = $keys->{ACTIVITY};

    if (not grep (/^$owner$/, @{$self->{PKI_REALM}->{$realm}->{ROLES}}))
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_SERVER_ACL_AUTHORIZE_ILLEGAL_AFFECTED_ROLE",
            params  => {PKI_REALM     => $realm,
                        ACTIVITY      => $activity,
                        AFFECTED_ROLE => $owner,
                        AUTH_ROLE     => $user});
    }

    if (not grep (/^$user$/, @{$self->{PKI_REALM}->{$realm}->{ROLES}}))
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_SERVER_ACL_AUTHORIZE_ILLEGAL_AUTH_ROLE",
            params  => {PKI_REALM     => $realm,
                        ACTIVITY      => $activity,
                        AFFECTED_ROLE => $owner,
                        AUTH_ROLE     => $user});
    }

    if (not grep (/^$activity$/,
                  @{$self->{PKI_REALM}->{$realm}->{ACL}->{$owner}->{$user}})
        and
        not grep (/^\*$/,
                  @{$self->{PKI_REALM}->{$realm}->{ACL}->{$owner}->{$user}}))
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_SERVER_ACL_AUTHORIZE_PERMISSION_DENIED",
            params  => {PKI_REALM     => $realm,
                        ACTIVITY      => $activity,
                        AFFECTED_ROLE => $owner,
                        AUTH_ROLE     => $user});
    }
    return 1;
}

1;
__END__
