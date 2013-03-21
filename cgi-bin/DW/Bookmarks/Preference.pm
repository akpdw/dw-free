#!/usr/bin/perl
#
# DW::BookmarkPreference
#
# Settings for User Bookmarks.  These are used as global settings/overrides
# for individual bookmarks.
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Bookmarks::Preference;
use strict;
use warnings;

use base 'DW::BaseDbObj';

sub memcache_enabled { 0 }
sub _obj_props {
    return qw( userid kwid security allowmask comment );
}

sub _tablename { "bookmarks_prefs" }

sub _memcache_key_prefix            { "bpref" }
sub _memcache_version { "1" }


# populates the basic keys for a Bookmark; everything else is
# loaded from absorb_row
sub _skeleton {
    my ( $class, $id ) = @_;
    return bless {
        _obj_id => $id,
    };
}

# create
sub create {
    my ( $class, $opts ) = @_;

    my %local_opts = %$opts;
    # we need to convert the tag to a kwid
    $local_opts{kwid} = LJ::get_sitekeyword_id( $local_opts{tag}, 1 );
    $local_opts{userid} = $local_opts{u}->{userid};

    return $class->_create( \%local_opts );
}

# Gets the BookmarkPreference for the given tag
sub for_tag {
    my ( $class, $u, $tag ) = @_;

    my $dbr = LJ::get_db_reader();

    my $sth = $dbr->prepare( "SELECT * FROM " . $class->_tablename . " bp INNER JOIN sitekeywords sk ON bp.kwid = sk.kwid WHERE userid=? AND keyword=?" ); 
    $sth->execute( $u->{userid}, $tag );
    LJ::throw( $dbr->errstr ) if $dbr->err;

    my @objs;
    while ( my $row = $sth->fetchrow_hashref ) {
        my $obj = $class->_new_from_row( $row );
        push @objs, $obj;
#        $obj->_store_to_memcache;
#        push @objids, $obj->{_obj_id};
    }
#    $class->_store_items($u, \@objids);
    # should be either 0 or 1
    return @objs ? $objs[0] : undef;
}

# returns all of the objects for the requested user.
sub all_for_user {
    my ( $class, $u ) = @_;

    # we require a user here.
    $u = LJ::want_user($u) or LJ::throw("no user");

    return $class->_all_items_by_value( "userid", $u->{userid} );
}

## Accessors
# returns the user
sub user {
    my $self = $_[0];

    if ( ! $self->{user} ) {
        my $user = LJ::load_userid( $self->{userid} );
        $self->{user} = $user;
    }
    return $self->{user};
}

# returns the security of this bookmark (public, private, usemask)
sub security {
    return $_[0]->{security};
}

# sets the security
sub set_security {
    my ( $self, $security ) = @_;
    $self->{security} = $security;
}

# returns the comment
sub comment {
    return $_[0]->{comment};
}

# returns the tag for this bookmark
sub tag {
    my ( $self ) = @_;

    unless ( $self->{tag} ) {
        if ( $self->{kwid} ) {
            my $tag = LJ::get_interest( $self->{kwid} );
            $self->{tag} = $tag;
        }
    }
    return $self->{tag};
}

1;

