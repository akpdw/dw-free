#!/usr/bin/perl
#
# DW::Bookmarks::Access
#
# Accessor class for Bookmarks.  This is used to access or modify 
# individual or groups of Bookmarks.
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.


package DW::Bookmarks::Accessor;
use strict;
use warnings;

use base 'DW::Bookmarks::Bookmark';

# returns all of the objects for the requested user.
# NOTE:  this actually returns all of the raw objects.  If you want 
# a view for a user, use visible_by_user
sub all_for_user {
    my ( $class, $u ) = @_;

    # we require a user here.
    $u = LJ::want_user($u) or LJ::throw("no user");

    return $class->_all_items_by_value( "userid", $u->{userid} );
}

# returns all of the objects for the requested user.
# NOTE:  this actually returns all of the raw objects.  If you want 
# a view for a user, use visible_by_user
sub all_ids_for_user {
    my ( $class, $u ) = @_;

    # we require a user here.
    $u = LJ::want_user($u) or LJ::throw("no user");

    return $class->_keys_by_value( "userid", $u->{userid} );
}

# returns public bookmarks with the given tag.
sub by_tag {
    my ( $class, $tag ) = @_;

    my @objs;
    
    #warn("getting tagid for tag $tag");
    
    my $tagid = LJ::get_sitekeyword_id( $tag, 0 );
    #warn( "got kw $tagid for tag '$tag'" );
    return @objs unless ( $tagid );
    
    my $ids;
    # check memcache
    if ( $class->memcache_query_enabled ) {
        $ids = $class->_load_keys( "tags:public", $tagid );
    }  
    # if we didn't get the keys from memcache, load them from the db
    unless ( $ids && ref $ids eq 'ARRAY' && scalar @$ids > 1 ) {
        my $dbr = $class->get_db_reader();
        
        #warn("running SELECT b.id FROM " . $class->_tablename . " b INNER JOIN bookmarks_tags bt ON bt.bookmarkid = b.id INNER JOIN public_bookmark_kws pb ON b.id = pb.bookmarkid AND bt.kwid = pb.kwid WHERE pb.keyword = ? ORDER BY b.last_modified DESC LIMIT 50" );
        $ids = $dbr->selectcol_arrayref( "SELECT b.id FROM " . $class->_tablename . " b INNER JOIN bookmarks_tags bt ON bt.bookmarkid = b.id INNER JOIN public_bookmark_kws pb ON b.id = pb.bookmarkid AND bt.kwid = pb.kwid WHERE pb.kwid = ? ORDER BY b.last_modified DESC LIMIT 200", undef, $tagid );
        LJ::throw( $dbr->errstr ) if $dbr->err;
        
        if ( $class->memcache_query_enabled ) {
            $class->_store_keys( "tags:public", $tagid, $ids );
        }
    }
    
    #warn("got " . @$ids . " results:  " . join( ',', @$ids ));
    @objs = $class->_load_objs_from_keys( $ids );
    
    #warn("got " . @objs . " objects for by_tag");
    return @objs;
}

# returns the bookmarks with the given tag for the requested user.
# NOTE:  this actually returns all of the raw objects.  If you want 
# a view for a user, use visible_by_user_tag
sub by_tag_for_user {
    my ( $class, $u, $tag, $remote ) = @_;
    
    $u = LJ::want_user($u) or LJ::throw("no user");
    my @objs;

#    warn("getting tagid for tag $tag");

    my $tagid = LJ::get_sitekeyword_id( $tag, 0 );
    return @objs unless ( $tagid );
    
    my $dbr = $class->get_db_reader( $u );

#    warn("running querySELECT b." . join ( ', b.' , ( $class->_obj_keys, $class->_obj_props ) ) . " FROM " . $class->_tablename . " b, bookmarks_tags bt WHERE b.userid = ? AND b.id = bt.bookmarkid AND bt.kwid = ?, values " . $u->{userid} . ", " . $tagid );
    my $sth = $dbr->prepare( "SELECT b." . join ( ', b.' , ( $class->_obj_keys, $class->_obj_props ) ) . " FROM " . $class->_tablename . " b, bookmarks_tags bt WHERE b.userid = ? AND b.id = bt.bookmarkid AND bt.kwid = ?");
    $sth->execute( $u->{userid}, $tagid );
    LJ::throw( $dbr->errstr ) if $dbr->err;

    my @objids;
    while ( my $row = $sth->fetchrow_hashref ) {
        my $obj = $class->_new_from_row( $row );
        push @objs, $obj;
    }
    return @objs;

}

# returns the tags used by a given user, as visible to the remote user,
# as well as the tag counts. return value is an arrayref of hashes 
# (tag, tagcount), ordered by count
sub visible_tags_for_user {
    my ( $class, $u, $remote ) = @_;

    my $userid = $u->userid;

    # three possibilities here:  $remote is $u, in which case show them
    # all, $remote is not in $u's access list, in which case show only the
    # public ones, or $remote is in $user's access list, in which case we 
    # have to look.
    # FIXME for now just handle two cases: all vs public
    my $show_all = ( $remote && $u == $remote );

    # check memcache
    my $results;
    if ( $class->memcache_query_enabled ) {
        if ( $show_all) {
            #warn("getting all tags");
            $results = $class->_load_keys( "userid:alltags", $userid );
        } else {
            #warn("getting public tags");
            $results = $class->_load_keys( "userid:publictags", $userid );
        }
    }  
    # if we didn't get the keys from memcache, load them from the db
    unless ( $results && ref $results eq 'ARRAY' && scalar @$results > 1 ) {
        my $dbr = $class->get_db_reader( $u );
        #warn("getting tags -- calling db");
        my $queryresults;
        if ( $show_all ) {
            #warn("getting all tags");
            $queryresults = $dbr->selectall_arrayref(
                "SELECT DISTINCT(sk.keyword) AS tag, " .
                "    COUNT(sk.keyword) AS tagcount " .
                "  FROM bookmarks_tags bt " .
                "  INNER JOIN sitekeywords sk " . 
                "    ON bt.kwid = sk.kwid " . 
                "  INNER JOIN bookmarks b " .
                "    ON b.id = bt.bookmarkid " .
                "  WHERE b.userid = ? " .
                "  GROUP BY sk.keyword" .
                "  ORDER BY tagcount DESC, sk.keyword ASC", undef, $userid );
        } else {
            #warn("getting public tags -- using pubkeywords");
            $queryresults = $dbr->selectall_arrayref( 
                "SELECT DISTINCT(pk.keyword) AS tag, " .
                "    COUNT(pk.keyword) AS tagcount " .
                "  FROM public_bookmark_kws pk " .
                "  INNER JOIN bookmarks b " .
                "    ON b.id = pk.bookmarkid " .
                "  WHERE b.userid = ? " .
                "  GROUP BY pk.keyword" .
                "  ORDER BY tagcount DESC, pk.keyword ASC", undef, $userid );
        }
        LJ::throw( $dbr->errstr ) if $dbr->err;
        foreach my $row ( @$queryresults ) {
            push @$results, { tag => $row->[0], tagcount => $row->[1] };
        }
        if ( $class->memcache_query_enabled ) {
            if ( $show_all) {
                $class->_store_keys( "userid:alltags", $userid, $results );
            } else {
                $class->_store_keys( "userid:publictags", $userid, $results );
            }
        }
    }
    
    return $results;
}

# returns all the bookmarks for the given user that are visible to
# the remote user.
sub visible_by_user {
    my ( $class, $u, $remote ) = @_;
    
    my @allbookmarks = $class->all_for_user( $u );
    
    #warn("visible_by_user:  allbookmars = " . scalar @allbookmarks);
    my $bookmarks = $class->filter_bookmarks( \@allbookmarks, $remote );
    #warn("vis by user filtered = " . @$bookmarks );

    return @$bookmarks;
}

# returns all the bookmarks in the given set that are visible by the
# remote user.
sub page_visible_by_remote {
    my ( $class, $ids, $remote, $opts ) = @_;
    
    my @bookmark_ids = @$ids;

    my $page = {};

    if ( $opts ) {
        my $page_size = ( $opts->{'page_size'} ?  $opts->{'page_size'}+0 : 25 );
        warn("page_size in accessor=" . $page_size);
        my $pivot = $opts->{after} || $opts->{before} || 0;
        my $index = 0;
        if ( $pivot ) {
            warn("checking for $pivot");
            my $found = 0;
            foreach my $id ( @bookmark_ids ) {
                if ( $id == $pivot ) {
                    #warn("found pivot!");
                    $found = 1;
                    # break; FIXME
                } else {
                    if ( ! $found ) {
                        $index++;
                    }
                }
            }
            # if we don't find the requested id, show the first page
            if ( ! $found ) {
                $index = 0;
            }
        }
        
        my $start_index;
        if ( $opts->{after} ) {
            $start_index = $index + 1;
        } elsif ( $opts->{before} ) {
            $start_index = $index - 1;
        } else {
            $start_index = 0;
        }

        my $page_before = 0;
        my $page_after = 0;
        
        if ( $start_index > 0 ) {
            splice( @bookmark_ids, 0, $start_index );
            $page_before = $bookmark_ids[0];
        }
        if ( scalar @bookmark_ids > $page_size ) {
            splice( @bookmark_ids, $page_size );
            $page_after = $bookmark_ids[ scalar @bookmark_ids - 1];
        }
        
        my @items = $class->_load_objs_from_keys( \@bookmark_ids );
        $page = {
            items => \@items,
            page_before => $page_before,
            page_after => $page_after,
        };
    }
    return $page;
}

# returns all the bookmarks for the given user with the given tag that are 
# visible to the remote user.
sub visible_by_user_tag {
    my ( $class, $u, $tag, $remote ) = @_;
    
    my @allbookmarks = $class->by_tag_for_user( $u, $tag, $remote );
    
    #warn("visible_by_user_tag:  allbookmars = " . scalar @allbookmarks);
    my $bookmarks = $class->filter_bookmarks( \@allbookmarks, $remote );
    return @$bookmarks;
}

# returns all bookmarks on the given entry that are visible to the 
# remote user.
sub visible_by_entry {
    my ( $class, $entry, $remote ) = @_;

    # FIXME
    my $dbr = $class->get_db_reader();

    # FIXME filter out preference overrides
    my $sth = $dbr->prepare( "SELECT b." . join ( ', b.' , ( $class->_obj_keys, $class->_obj_props ) ) . " FROM " . $class->_tablename . " b WHERE b.type='entry' AND b.journalid = ? AND b.ditemid = ?");
    $sth->execute( $entry->journal->{userid}, $entry->ditemid );
    LJ::throw( $dbr->errstr ) if $dbr->err;

    my @objs;
    while ( my $row = $sth->fetchrow_hashref ) {
        my $obj = $class->_new_from_row( $row );
        push @objs, $obj;
    }

    my $bookmarks = $class->filter_bookmarks( \@objs, $remote );

    return @$bookmarks;
}

# returns the given bookmark, as made visible to the given user
sub visible_by_id {
    my ( $class, $u, $id, $remote ) = @_;

    my $bookmark = $class->by_id( $id );
    my @bookmark_array = ( $bookmark );
    my $bookmarks = $class->filter_bookmarks( \@bookmark_array, $remote );

    if ( scalar @$bookmarks ) {
        return $bookmarks->[0];
    } else {
        return undef;
    }
}

# returns (readable) bookmarks by id
sub visible_by_ids {
    my ( $class, $remote, $ids ) = @_;
    
    # FIXME if you send in a bookmark id that doesn't exist, we should
    # just skip over it, not return an empty bookmark
    my @bookmark_array = $class->_load_objs_from_keys( $ids );
    my $bookmarks = $class->filter_bookmarks( \@bookmark_array, $remote );

    return $bookmarks;
}

# filters the given set of Bookmark objects by the given remote user.
sub filter_bookmarks {
    my ( $class, $bookmarks, $remote, $opts ) = @_;

    # if we've included a custom filter, use it.
    if ( $opts && $opts->{filter} ) {
        return $opts->filter( $class, $bookmarks, $remote, $opts );
    }

    #warn ("filtering...");
    my @visible = ();
    foreach my $bookmark ( @$bookmarks ) {
        #warn ("filtering bookmark");
        if ( $bookmark ) {
            if ( $bookmark->visible_to( $remote ) ) {
                #warn ("visible.");
                #warn("tags=" . $bookmark->tags );
                $bookmark->filter_tags( $remote );
                #warn ("tags filtered.");
                if ( $bookmark->tags ) {
                    #warn ("tags set; pushing to visible.");
                    push @visible, $bookmark;
                }
            }
        }
    }
    return \@visible;
}

# returns the (recent) bookmarks for the user's watch list
sub by_watch_list {
    my ( $class, $u, $remote ) = @_;

    $u = LJ::want_user($u) or LJ::throw("no user");

    my @retval;

    my @watched_users = $u->watched_users;
    foreach my $watched_user ( @watched_users ) {
        push @retval,  $class->visible_by_user( $watched_user, $remote );
    }
    @retval = sort { $a->created <=> $b->created } @retval;
    return @retval;
}

# returns the (recent) bookmarks for the user's network
sub by_network {
    my ( $class, $u, $remote ) = @_;

    $u = LJ::want_user($u) or LJ::throw("no user");

    my @retval;

    my @network = $u->network;
    foreach my $network_user ( @network ) {
        push @retval,  $class->visible_by_user( $network_user, $remote );
    }
    @retval = sort { $a->created <=> $b->created } @retval;
    return @retval;
}

# returns the most popular bookmarks
sub popular_bookmarks {
    my ( $class ) = @_;

    #warn("checking popular bookmarks");
    my $results;
    #if ( $class->memcache_query_enabled ) {
    #    $results = $class->_load_keys( "top", 1 );
    #}
    unless ($results && ref $results eq 'ARRAY' && scalar @$results > 1 ) {
        my $dbr = $class->get_db_reader();

        my $since = time - ( 14 * 24 * 3600 );
        
        my $urls = $dbr->selectall_arrayref ( 
            "SELECT DISTINCT(url), COUNT(url) AS count " .
            "  FROM bookmarks " .
            "  WHERE security = 'public' " .
            "  AND type = 'url' " .
            "  AND created > ? " .
            "    GROUP BY url " .
            "    ORDER BY count DESC " .
            "    LIMIT 25", undef, $since );
        LJ::throw( $dbr->errstr ) if $dbr->err;

        my @temp;
        foreach my $url ( @$urls ) {
            my $tags = $class->popular_tags_for_url( $url->[0], $since );
            my $title = $class->popular_title_for_url( $url->[0], $since );
            my $hashref = {};
            $hashref->{'url'} = $url->[0];
            $hashref->{'title'} = $title;
            $hashref->{'count'} = $url->[1];
            $hashref->{'tags'} = $tags;
            push @temp, $hashref;
        }
        $results = \@temp;

        # FIXME ?? get entry/comments, too ??
        #if ( $class->memcache_query_enabled ) {
        #    $class->_store_keys( "top", 1, $results );
        #}
    }
    return $results;
}

# returns the most recent bookmarks
sub recent_bookmarks {
    my ( $class ) = @_;

    warn("checking recent bookmarks");
    my $results;
    #if ( $class->memcache_query_enabled ) {
    #    $results = $class->_load_keys( "recent", 1 );
    #}
    unless ($results && ref $results eq 'ARRAY' && scalar @$results > 1 ) {
        my $dbr = $class->get_db_reader();
        
        my $ids = $dbr->selectcol_arrayref ( 
            "SELECT id " .
            "  FROM public_bookmarks " .
            "  WHERE security = 'public' " .
            "    ORDER BY created DESC " .
            "    LIMIT 50", undef);
        LJ::throw( $dbr->errstr ) if $dbr->err;

        #warn("got ids $ids");
        my @items = $class->_load_objs_from_keys( $ids );
        $results = \@items;
        
        # FIXME ?? get entry/comments, too ??
        #if ( $class->memcache_query_enabled ) {
        #    $class->_store_keys( "recent", 1, $results );
        #}
    }
    return $results;
}

# returns the top recent tags
sub recent_tags {
    my ( $class, $count ) = @_;

    my $dbr = $class->get_db_reader();

    my $sth = $dbr->prepare( 
        "SELECT DISTINCT(pkw.keyword) AS tag, " .
        "COUNT(pkw.keyword) AS tagcount " .
        "FROM public_bookmark_kws pkw " .
        "INNER JOIN public_bookmarks pbk " .
        "ON pbk.id = pkw.bookmarkid " .
        "WHERE pbk.created > ? " .
        "GROUP BY pkw.keyword " .
        "ORDER BY tagcount " .
        "DESC LIMIT ?" );

    my $recent = time - ( 14 * 24 * 3600 );
    $sth->execute( $recent, $count );
    LJ::throw( $dbr->errstr ) if $dbr->err;

    my @kws;
    while ( my $row = $sth->fetchrow_hashref ) {
        warn("adding " . $row->{tag} . ", " . $row->{tagcount});
        push @kws, $row;
    }

    warn("kws = " . @kws);
    return \@kws;
}

# loads the most popular recent tags for the given url from the database
# and returns them
sub popular_tags_for_url {
    my ( $class, $url, $since ) = @_;

    my $dbr = $class->get_db_reader();
    
    #warn( "checking popular tags for $url");
    my $tags = $dbr->selectall_arrayref ( 
        "SELECT DISTINCT(pbk.keyword), COUNT(pbk.keyword) AS count " .
        "  FROM public_bookmarks b " .
        "  INNER JOIN public_bookmark_kws pbk " .
        "  ON b.id = pbk.bookmarkid " .
        "  WHERE b.url = ? " .
        "  AND b.created > ? " .
        "    GROUP BY pbk.keyword " .
        "    ORDER BY count DESC " .
        "    LIMIT 5", undef, $url, $since );
    LJ::throw( $dbr->errstr ) if $dbr->err;
    
    my @retval = map { $_->[0] } @$tags;
    
    return \@retval;
}

# loads the most popular recent title for the given url from the database
# and returns it
sub popular_title_for_url {
    my ( $class, $url, $since ) = @_;

    my $dbr = $class->get_db_reader();
    
    #warn( "checking popular title for $url");
    my $title = $dbr->selectrow_arrayref ( 
        "SELECT b.title, COUNT(b.title) AS count " .
        "  FROM public_bookmarks b " .
        "  WHERE b.url = ? " .
        "  AND b.created > ? " .
        "    GROUP BY b.title " .
        "    ORDER BY count DESC " .
        "    LIMIT 1", undef, $url, $since );
    LJ::throw( $dbr->errstr ) if $dbr->err;
    
    my $retval = $title->[0];
    return $retval;
}

#returns the top bookmarks for the site. return value is an arrayref of hashes 
# (tag, tagcount), ordered by count
sub top_tags {
    my ( $class, $count ) = @_;

    warn("checking top tags");
    my $dbr = $class->get_db_reader();

    my $sth = $dbr->prepare( "SELECT DISTINCT(keyword) AS tag, COUNT(bookmarkid) AS tagcount FROM public_bookmark_kws GROUP BY keyword ORDER BY tagcount DESC, keyword ASC LIMIT ?" );

    $sth->execute( $count );
    LJ::throw( $dbr->errstr ) if $dbr->err;

    my @returnvalue;
    while ( my $row = $sth->fetchrow_hashref ) {
        warn("adding " . $row->{keyword} . " to tags");
        push @returnvalue, $row;
    }

    return \@returnvalue;
}

# tries to find matching tags for the user given the substring typed.
sub match_tags {
    my ( $class, $u, $substring ) = @_;

    my $searchstr = $substring . "%";

    my @kws;

    # first get user's keywords that match
    my $dbr = $class->get_db_reader( $u );

    my $sth = $dbr->prepare( "SELECT DISTINCT(sk.keyword), COUNT(bt.bookmarkid) AS kwcount FROM bookmarks b JOIN bookmarks_tags bt ON b.id = bt.bookmarkid JOIN sitekeywords sk ON bt.kwid = sk.kwid WHERE b.userid = ? AND sk.keyword LIKE ? GROUP BY sk.keyword ORDER BY kwcount DESC LIMIT 10" );

    $sth->execute( $u->{userid}, $searchstr );
    LJ::throw( $dbr->errstr ) if $dbr->err;
    
    while ( my $row = $sth->fetchrow_hashref ) {
        push @kws, $row->{keyword};
    }

    if ( scalar @kws >= 10 ) {
        return @kws;
    }
    
    # if we haven't gotten enough matches for the user, check the public tags
    $sth = $dbr->prepare( "SELECT DISTINCT(keyword), COUNT(bookmarkid) AS kwcount FROM public_bookmark_kws WHERE keyword LIKE ? GROUP BY keyword ORDER BY kwcount DESC LIMIT 10" );

    $sth->execute( $searchstr );
    LJ::throw( $dbr->errstr ) if $dbr->err;

    while ( my $row = $sth->fetchrow_hashref ) {
        push @kws, $row;
    }

    return @kws;
}

# Adds the provided tag(s) to the given set of bookmarks.
sub add_tags {
    my ( $class, $bookmarks, $tags, $remote ) = @_;

    my @args = ();
    my @argcount = ();
    my %tagmap = ();
    # get each of the tag id
    foreach my $tag ( @$tags ) {
        $tagmap{$tag} =  LJ::get_sitekeyword_id( $tag, 1 );
    }

    my @editable_bookmarks = ();
    foreach my $bookmark ( @$bookmarks ) {
        if ( $bookmark->editable_by( $remote ) ) {
            push @editable_bookmarks, $bookmark;
            foreach my $tag ( keys %tagmap ) {
                unless ( $bookmark->has_tag( $tag ) ) {
                    push @args, ( $bookmark->id, $tagmap{$tag} );
                    push @argcount, 1;
                }
            }
        }
    }
    my $qs = join( ', ', map { '(?,?)' } @argcount );
    
    my $dbh = $class->get_db_writer( $remote );

    
    if ( $qs ) {
        $dbh->do( "INSERT INTO bookmarks_tags ( bookmarkid, kwid ) values $qs", undef, @args );
    
        LJ::throw($dbh->errstr) if $dbh->err;

        foreach my $bookmark ( @editable_bookmarks ) {
            $bookmark->_clear_cache();
            $bookmark->_clear_associated_caches();
        }
    }
}

# Removes the provided tag(s) from the given set of bookmarks.
sub remove_tags {
    my ( $class, $bookmarks, $tags, $remote ) = @_;

    my @bmarkids = ();

    my @editable_bookmarks = ();
    foreach my $bookmark ( @$bookmarks ) {
        if ( $bookmark->editable_by( $remote ) ) {
            push @editable_bookmarks, $bookmark;
            push @bmarkids, $bookmark->id;
        }
    }
    my $bookmark_qs = join( ', ', map { '?' } @bmarkids );
    my $kw_qs = join( ', ', map { '?' } @$tags );
    my @args = ( @bmarkids, @$tags );
    
    my $dbh = $class->get_db_writer( $remote );

    $dbh->do( "DELETE FROM bookmarks_tags WHERE bookmarkid IN ($bookmark_qs) AND kwid IN ( SELECT kwid FROM sitekeywords WHERE keyword IN ( $kw_qs ) )", undef, @args );
    
    LJ::throw($dbh->errstr) if $dbh->err;
    
    foreach my $bookmark ( @editable_bookmarks ) {
        $bookmark->_clear_cache();
        $bookmark->_clear_associated_caches();
    }
}

# Removes the provided tag(s) from the given set of bookmarks.
sub update_security {
    my ( $class, $bookmarks, $security, $allowmask, $remote ) = @_;

    my @bmarkids = ();

    my @editable_bookmarks = ();
    foreach my $bookmark ( @$bookmarks ) {
        if ( $bookmark->editable_by( $remote ) ) {
            push @editable_bookmarks, $bookmark;
            push @bmarkids, $bookmark->id;
        }
    }
    my $bookmark_qs = join( ', ', map { '?' } @bmarkids );
    my @args = ( $security, $security eq 'usemask' ? $allowmask : 0, @bmarkids );

    my $dbh = $class->get_db_writer( $remote );

    $dbh->do( "UPDATE bookmarks SET security=?, allowmask=? WHERE id IN ($bookmark_qs)", undef, @args );
    
    LJ::throw($dbh->errstr) if $dbh->err;
    
    foreach my $bookmark ( @editable_bookmarks ) {
        $bookmark->_clear_cache();
        $bookmark->_clear_associated_caches();
    }
}

# Deletes a group of bookmarks
sub delete_multi {
    my ( $class, $bookmarks, $remote ) = @_;

    my @bmarkids = ();
    my @editable_bookmarks = ();
    foreach my $bookmark ( @$bookmarks ) {
        if ( $bookmark->editable_by( $remote ) ) {
            push @editable_bookmarks, $bookmark;
            push @bmarkids, $bookmark->id;
        }
    }

    my $bookmark_qs = join( ', ', map { '?' } @bmarkids );
    my @args = ( @bmarkids );
    
    my $dbh = $class->get_db_writer( $remote );

    $dbh->do( "DELETE FROM bookmarks_tags WHERE bookmarkid IN ($bookmark_qs)", undef, @args );
    LJ::throw($dbh->errstr) if $dbh->err;
    
    $dbh->do( "DELETE FROM bookmarks WHERE id IN ($bookmark_qs)", undef, @args );
    LJ::throw($dbh->errstr) if $dbh->err;
    
    foreach my $bookmark ( @editable_bookmarks ) {
        $bookmark->_clear_cache();
        $bookmark->_clear_associated_caches();
    }
}

# creates an entry for the selected bookmarks
# FIXME
sub create_entry {
    my ( $class, $idlist ) = @_;

    return 1;
}

# creates a search hash from a query string
sub create_searchterm {
    my ( $class, $key, $comparator, @values ) = @_;

    if ( $key eq 'untagged' ) {
        warn("checking untagged term");
        my $term = {
            whereclause => 'not exists (select * from bookmarks_tags bt where bt.bookmarkid = bookmarks.id)',
        }; 
        return $term;
    } else {
        return DW::Bookmarks::Bookmark->create_searchterm( $key, $comparator, @values );
    }
}


1;

