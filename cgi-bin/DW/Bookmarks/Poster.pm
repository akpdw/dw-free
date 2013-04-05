#!/usr/bin/perl
#
# DW::Bookmarks::Poster
#
# Creates and manages entry posts of bookmarks. 
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.


package DW::Bookmarks::Poster;
use strict;
use warnings;

use DW::Bookmarks::Accessor;

sub _tablename { return "bookmark_post" }

# DB utils
sub get_db_writer {
    return LJ::get_db_writer();
}
sub get_db_reader {
    return LJ::get_db_reader();
}

# gets the list of bookmark ids in the currently-in-progress bookmark
# post for the given user.
sub current_post {
    my ( $class, $u ) = @_;

    my $results = $class->_load_from_memcache( $u );
    if ( ! defined $results || scalar @$results < 1 ) {
        $results = $class->_load_from_db( $u );
        if ( defined $results && scalar @$results > 1 ) {
            $class->_save_to_memcache( $u, $results );
        }
    }

    my $bookmarks = [];
    if ( $results && ref $results && scalar @$results > 0 ) {
        $bookmarks = DW::Bookmarks::Accessor->visible_by_ids( $u, $results );
    }

    return $bookmarks;
}

# adds a set of bookmark ids to the post list
sub add_bookmarks {
    my ( $class, $u, @bmarkids ) = @_;

    if ( scalar @bmarkids > 0 ) {
        $class->_save_to_db( $u, @bmarkids );
    }
    $class->_clear_memcache( $u );
}

# removes a set of bookmark ids from the post list
sub remove_bookmarks {
    my ( $class, $u, @bmarkids ) = @_;

    if ( scalar @bmarkids > 0 ) {
        $class->_delete_from_db( $u, @bmarkids );
        $class->_clear_memcache( $u );
    }
}

# clears the current post 
sub clear {
    my ( $class, $u ) = @_;

    $class->_delete_all_from_db( $u );
    $class->_clear_memcache( $u );
    
}

# loads the list from the db
sub _load_from_db {
    my ( $class, $u ) = @_;
    my $dbr = $class->get_db_reader();

    #warn("running SELECT bookmarkid FROM " . $class->_tablename . " WHERE userid = ?");
    my $results = $dbr->selectcol_arrayref( "SELECT bookmarkid FROM " . $class->_tablename . " WHERE userid = ?", undef, $u->userid );

    #warn ("got results $results ( " . scalar @$results . ")");
    return $results;
    
}

# saves the list to memcache
sub _save_to_db {
    my ( $class, $u, @bookmarks ) = @_;

    my $dbh = $class->get_db_writer();
    my @bmarkids = map { $_->id } @bookmarks;
    my $userid = $u->userid;
    my $bookmark_qs = join( ', ', map { "($userid, $_ )" } @bmarkids );
    my $sql = "INSERT IGNORE INTO " . $class->_tablename . "  ( userid, bookmarkid ) values $bookmark_qs";
    $dbh->do( $sql, undef );
    LJ::throw( $dbh->err ) if ( $dbh->err );
}

# saves the list to memcache
sub _delete_from_db {
    my ( $class, $u, @bookmarks ) = @_;

    my $dbh = $class->get_db_writer();
    my $bookmark_qs = join( ', ', map { '?' } @bookmarks );
    my @bmarkids = map { $_->id } @bookmarks;
    my $userid = $u->userid;
    my @query_args = join( ', ', map { '?' } @bmarkids );
    #warn(" running DELETE FROM " . $class->_tablename . " WHERE userid = ? AND bookmarkid IN ( $bookmark_qs ) with query args @bmarkids \n");
    $dbh->do( "DELETE FROM " . $class->_tablename . " WHERE userid = ? AND bookmarkid IN ( $bookmark_qs )", undef, $u->userid, @bmarkids );
    LJ::throw( $dbh->err ) if ( $dbh->err );
}

sub _delete_all_from_db {
    my ( $class, $u ) = @_;

    my $dbh = $class->get_db_writer();
    $dbh->do( "DELETE FROM " . $class->_tablename . " where userid = ?", undef, $u->userid );
    LJ::throw( $dbh->err ) if ( $dbh->err );
}

# loads the list from memcache
sub _load_from_memcache {
    # FIXME
    my @returnvalue = ();
    return \@returnvalue;
}

# saves the list to memcache
sub _save_to_memcache {
    # FIXME
    my @returnvalue = ();
    return \@returnvalue;

}

# clears memcache for this user
sub _clear_memcache {
    # FIXME
}


1;

