# Author: Stephen Hemminger <shemminger@vyatta.com>
# Date: 2009
# Description: vyatta interface management

# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2008 Vyatta, Inc.
# All Rights Reserved.
# **** End License ****

package Vyatta::Interface;

use strict;
use warnings;
use Vyatta::Config;
use Vyatta::Misc;
use base 'Exporter';
our @EXPORT = qw(IFF_UP IFF_BROADCAST IFF_DEBUG IFF_LOOPBACK 
	          IFF_POINTOPOINT IFF_RUNNING IFF_NOARP
		  IFF_PROMISC IFF_MULTICAST);


use constant { 
    IFF_UP		=> 0x1,		# interface is up
    IFF_BROADCAST	=> 0x2,		# broadcast address valid
    IFF_DEBUG		=> 0x4,		# turn on debugging
    IFF_LOOPBACK	=> 0x8,		# is a loopback net
    IFF_POINTOPOINT	=> 0x10,	# interface is has p-p link
    IFF_NOTRAILERS	=> 0x20,	# avoid use of trailers
    IFF_RUNNING		=> 0x40,	# interface RFC2863 OPER_UP
    IFF_NOARP		=> 0x80,	# no ARP protocol
    IFF_PROMISC		=> 0x100,	# receive all packets
    IFF_ALLMULTI	=> 0x200,	# receive all multicast packets
    IFF_MASTER		=> 0x400,	# master of a load balancer
    IFF_SLAVE		=> 0x800,	# slave of a load balancer
    IFF_MULTICAST	=> 0x1000,	# Supports multicast
    IFF_PORTSEL		=> 0x2000,      # can set media type
    IFF_AUTOMEDIA	=> 0x4000,	# auto media select active
    IFF_DYNAMIC		=> 0x8000,	# dialup device with changing addresses
    IFF_LOWER_UP	=> 0x10000,	# driver signals L1 up
    IFF_DORMANT		=> 0x20000,	# driver signals dormant
    IFF_ECHO		=> 0x40000,	# echo sent packets
};

#
# Mapping from name to attributes
#   path: configuration level below interfaces
#   vif:  places to look for vif (if any)
my %net_prefix = (
    '^adsl[\d]+$'  => { path => 'adsl',
		      vif => 'vif',    },
    '^bond[\d]+$'  => { path => 'bonding', 
		      vif => 'vif', },
    '^br[\d]+$'    => { path => 'bridge',
		      vif => 'vif' },
    '^eth[\d]+$'   => { path => 'ethernet',
		      vif => 'vif', },
    '^lo$'         => { path => 'loopback' },
    '^ml[\d]+$'    => { path => 'multilink',
		      vif => 'vif', },
    '^vtun[\d]+$'  => { path => 'openvpn' },
    '^wan[\d]+$'   => { path => 'serial',
		      vif  => ( 'cisco-hdlc vif', 'ppp vif', 
				'frame-relay vif' ), },
    '^tun[\d]+$'   => { path => 'tunnel' },
    '^wlm[\d]+$'   => { path => 'wireless-modem' },
    '^peth[\d]+$'  => { path => 'pseudo-ethernet',
		      vif => 'vif', },
    '^wlan[\d]+$'  => { path => 'wireless', vif => 'vif' },
);

# get list of interface types
sub interface_types {
    my @types = map { $net_prefix{$_}{path} } keys %net_prefix;
    return @types;
}

# new interface description object
sub new {
    my $that  = shift;
    my $name  = pop;
    my $class = ref($that) || $that;
    my ($dev, $vif);

    # need argument to constructor
    return unless $name;

    # Strip off vif from name
    if ( $name =~ m/(\w+)\.(\d+)/ ) {
        $dev = $1;
        $vif = $2;
    } else {
        $dev = $name;
    }

    foreach my $prefix (keys %net_prefix) {
        next unless $dev =~ /$prefix/;
        my $type    = $net_prefix{$prefix}{path};
        my $vifpath = $net_prefix{$prefix}{vif};

        # Interface name has vif, but this type doesn't support vif!
        return if ( $vif && !$vifpath );

        # Check path if given
        return if ( $#_ >= 0 && join( ' ', @_ ) ne $type );

        my $path = "interfaces $type $dev";
        $path .= " $vifpath $vif" if $vif;

	my $self = { 
	    name => $name,
	    type => $type,
	    path => $path,
	    dev  => $dev,
	    vif  => $vif,
	};

        bless $self, $class;
        return $self;
    }

    return; # nothing
}

## Field accessors
sub name {
    my $self = shift;
    return $self->{name};
}

sub path {
    my $self = shift;
    return $self->{path};
}

sub vif {
    my $self = shift;
    return $self->{vif};
}

sub physicalDevice {
    my $self = shift;
    return $self->{dev};
}

sub type {
    my $self = shift;
    return $self->{type};
}

## Configuration checks

sub configured {
    my $self   = shift;
    my $config = new Vyatta::Config;

    return $config->exists( $self->{path} );
}

sub disabled {
    my $self   = shift;
    my $config = new Vyatta::Config;

    $config->setLevel( $self->{path} );
    return $config->exists("disable");
}

sub mtu {
    my $self  = shift;
    my $config = new Vyatta::Config;

    $config->setLevel( $self->{path} );
    return $config->returnValue("mtu");
}

sub using_dhcp {
    my $self   = shift;
    my $config = new Vyatta::Config;
    $config->setLevel( $self->{path} );

    my @addr = grep { $_ eq 'dhcp' } $config->returnOrigValues('address');

    return if ($#addr < 0);
    return $addr[0];
}

## System checks

# return array of current addresses (on system)
sub address {
    my ($self, $type) = @_;

    return Vyatta::Misc::getIP($self->{name}, $type);
}

# return 

sub exists {
    my $self = shift;

    return ( -d "/sys/class/net/$self->{name}" );
}

sub flags {
    my $self = shift;

    open my $flags, '<', "/sys/class/net/$self->{name}/flags"
	or return;

    my $val = <$flags>;
    chomp $val;
    close $flags;
    return hex($val);
}

sub is_broadcast {
    my $self = shift;
    return $self->flags() & IFF_BROADCAST;
}

sub is_multicast {
    my $self = shift;
    return $self->flags() & IFF_MULTICAST;
}

sub is_pointtopoint {
    my $self = shift;
    return $self->flags() & IFF_POINTOPOINT;
}

sub is_loopback {
    my $self = shift;
    return $self->flags() & IFF_LOOPBACK;
}

# device exists and is online
sub up {
    my $self  = shift;
    my $flags = $self->flags();

    return $flags && ( $flags & IFF_UP );
}

# device exists and is running (ie carrier present)
sub running {
    my $self  = shift;
    my $flags = $self->flags();

    return $flags && ( $flags & IFF_RUNNING );
}

# device description information in kernel (future use)
sub description {
    my $self = shift;

    open my $ifalias, '<', "/sys/class/net/$self->{name}/ifalias"
	or return;
    my $description = <$ifalias>;
    close $ifalias;
    chomp $description if $description;

    return $description;
}

1;
