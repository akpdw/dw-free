#!/usr/bin/perl
#
# DW::Bookmarks::Bookmark
#
# Bookmarks made by users of local or external content.
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.


package DW::Bookmarks::Bookmark;
use strict;
use warnings;

use base 'DW::BaseDbObj';

sub _obj_props {
    return qw( userid type title security allowmask url comment journalid ditemid talkid last_modified created );
}

sub _obj_keys { "id" }

sub _tablename { "bookmarks" }

sub _default_order_by {
    return "ORDER BY created DESC";
}
sub _globalcounter_id { "B" }

sub _memcache_key_prefix            { "bmark" }
sub _memcache_version { "1" }

sub memcache_enabled { 1 }
sub memcache_query_enabled { 1 }
#sub memcache_enabled { 0 }
#sub memcache_query_enabled { 0 }

# populates the basic keys for a Bookmark; everything else is
# loaded from absorb_row
sub _skeleton {
    my ( $class, $id ) = @_;
    return bless {
        _obj_id => $id,
    };
}

# creates a new bookmark for the given user
sub create {
    my ( $class, $u, $opts ) = @_;
    
    my %local_opts = %$opts;
    $local_opts{userid} = $u->{userid};

    my $obj = $class->_create( \%local_opts );
    
    if ( $local_opts{tags} ) {
        $obj->set_tags( $local_opts{tags} );
    } else {
        $obj->set_tag_string( $local_opts{tag_string} );
    }
    $obj->save_tags();
    return $obj;
}

#validates the new bookmark.
sub validate {
    my ( $class, $opts ) = @_;
    
    my $errors = {};

    my $u = LJ::load_userid( $opts->{userid} );

    # required fields
    $errors->{user} = "user.invalid" unless $u;

    $errors->{type} = "type.required" unless $opts->{type};
    if ( $opts->{type} ) {
        $errors->{type} = "type.invalid" unless ( $opts->{type} eq 'url' ||  $opts->{type} eq 'entry' ||  $opts->{type} eq 'comment' );
        
        # entry check
        if ( $opts->{type} eq 'entry' || $opts->{type} eq 'comment' ) {
            $errors->{ditemid} = "ditemid.required" unless  $opts->{ditemid};
            # allow either journal or journalid
            if ( ! $opts->{journalid} ) {
                if ( $opts->{journal} ) {
                    my $j = eval { LJ::load_user( $opts->{journal} ); };
                    if ( $j ) {
                        $opts->{journalid} = $j->id;
                    }
                }
            }
            if ( ! $opts->{journalid} ) {
                $errors->{journalid} = "journal.required";
                $errors->{journal} = "journal.required";
            }
            
            if ( $opts->{ditemid} && $opts->{journalid} ) {
                my $journal = eval { LJ::want_user( $opts->{journalid} ); };

                my $entry = LJ::Entry->new( $journal, ditemid => $opts->{ditemid} );
                $errors->{entry} = "entry.invalid" unless ( $entry && $entry->visible_to( $u ) );
            }
        }

        # url check
        if ( $opts->{type} eq 'url' ) {
            $errors->{url} = "url.required" unless  $opts->{url};
        }
    }

    $errors->{title} = "title.required" unless  $opts->{title};

    $errors->{security} = "security.required" unless  $opts->{security};
    if ( $opts->{security} ) {
        $errors->{security} = "security.invalid" unless ( $opts->{security} eq 'public' ||  $opts->{security} eq 'usemask' ||  $opts->{security} eq 'private' );
    }

    if ( %$errors ) {
        #warn("errors");
        #foreach my $key ( keys %$errors ) {
        #    warn("error $key=" . $errors->{$key} );
        #}
        LJ::throw( $errors );
    }

    return 1;
}

# creates an entry for the selected bookmarks
# FIXME
sub create_entry {
    my ( $class, $idlist ) = @_;

    return 1;
}

## Object methods
# updates the bookmark
sub update {
    my ( $self ) = @_;

    $self->{last_modified} = time;
    $self->save_tags();

    $self->_update();
}

# deletes the given bookmark
sub delete {
    my ( $self ) = @_;

    # in this case, just use the batch version.
    my @list = ( $self );
    DW::Bookmarks::Accessor->delete_multi( \@list, $self->user );
}


# saves the current tag values to the database
# FIXME -- this isn't very efficient.
sub save_tags {
    my ( $self ) = @_;

    my @tags = @{$self->{tags}};

    my @args = ();
    foreach my $tag ( @tags ) {
        push @args, ( $self->{_obj_id}, LJ::get_sitekeyword_id( $tag, 1 ) );
    }
    my $qs = join( ', ', map { '(?,?)' } @tags );
    
    my $dbh = $self->get_db_writer( $self->user );

    # delete existing tags first
    $dbh->do( "DELETE FROM bookmarks_tags WHERE bookmarkid = ?", undef, $self->{_obj_id} );
    LJ::throw($dbh->errstr) if $dbh->err;

    # now create the current version of the tags
    if ( $qs ) {
        $dbh->do( "INSERT INTO bookmarks_tags ( bookmarkid, kwid ) values $qs", undef, @args );
    
        LJ::throw($dbh->errstr) if $dbh->err;
    }    
}

## Accessor methods
# returns the user
sub user {
    my $self = $_[0];

    if ( ! $self->{user} ) {
        my $user = LJ::load_userid( $self->{userid} );
        $self->{user} = $user;
    }
    return $self->{user};
}

# returns the title
sub title {
    return $_[0]->{title};
}

# returns the url for this Bookmark, either as an external url or as a created
# DW url.
sub url {
    my $self = $_[0];

    if ( $self->type eq 'url' ) {
        return $self->{url};
    } else {
        if ( $self->entry ) {
            return $self->entry->url;
        }
    }
    # if both of these failed, then the bookmark entry is invalid
    return undef;
}

# returns the entry that has been bookmarked
sub entry {
    my $self = $_[0];

    if ( ! $self->{entry} ) {
        if ( $self->journal ) {
            my $entry = LJ::Entry->new( $self->journal, ditemid => $self->ditemid );
            $self->{entry} = $entry;
        }
    }
    return $self->{entry};
}

# returns the journalid of this bookmark (if this is an entry or comment 
# bookmark)
sub journalid {
    return $_[0]->{'journalid'};
}

# returns the journal of this bookmark (if this is an entry or comment 
# bookmark)
sub journal {
    my $self = $_[0];

    if ( ! $self->{journal} ) {
        my $journal = LJ::load_userid( $self->journalid );
        $self->{journal} = $journal;
    }
    return $self->{journal};
}

# returns the ditemid of this bookmark (if this is an entry or comment 
# bookmark)
sub ditemid {
    return $_[0]->{ditemid};
}

# returns the talkid of this bookmark (if this is a comment bookmark)
sub talkid {
    return $_[0]->{talkid};
}

# returns the type of this bookmark (url, entry, or comment)
sub type {
    return $_[0]->{type};
}

# returns the tags for this bookmark as an array of strings
sub tags {
    my $self = $_[0];
    return @{$self->{tags}} if $self->{tags};

    # FIXME
    my $dbr = $self->get_db_reader( $self->user );
    #warn("running SELECT sk.keyword FROM sitekeywords sk, bookmarks_tags bt WHERE bt.bookmarkid = ? AND bt.kwid = sk.kwid");
    my $sth = $dbr->prepare( "
      SELECT sk.keyword, COALESCE(bp.security, 'public') AS security, bp.allowmask
      FROM bookmarks_tags bt
      JOIN bookmarks b
      ON   b.id=bt.bookmarkid
      JOIN sitekeywords sk
      ON   bt.kwid = sk.kwid
      LEFT JOIN bookmarks_prefs bp
      ON   bp.kwid = bt.kwid AND bp.userid = b.userid
      WHERE bt.bookmarkid = ? ");
    $sth->execute( $self->id );
    LJ::throw( $dbr->errstr ) if $dbr->err;

    my @tags;
    my $taginfo = {};
    #warn("running through taginfo");
    while ( my $row = $sth->fetchrow_hashref ) {
        push @tags, $row->{keyword};
        $taginfo->{ $row->{keyword} } = $row;
        #warn("added " . $row->{keyword} . " to taginfo");
    }
    
    $self->{tags} = \@tags;
    #warn("in load: taginfo size = " . scalar keys %$taginfo);
    $self->{taginfo} = $taginfo;
    return @tags;
}

# sets the tags property locally.  also updates the tag_string property.
# NOTE:  you still need to run save_tags() to store
# these in the database.
sub set_tags {
    my ( $self, $tags ) = @_;

    #warn("set_tags tags=$tags");
    # FIXME validate
    $self->{tags} = $tags;
    $self->{tag_string} = join( ', ', @$tags );
}

sub tag_string {
    my $self = $_[0];
    return $self->{tag_string} if $self->{tag_string};

    my @tags = $self->tags;
    $self->{tag_string} = join( ", ", @tags );
    return $self->{tag_string};
}

# sets the tag_string.  this also updates the tags property.
# NOTE:  you still need to run save_tags() to store
# these in the database.
sub set_tag_string {
    my ( $self, $tag_string ) = @_;
    
    # FIXME add in validation
    $self->{tag_string} = $tag_string;
    my @tags;
    if ( $tag_string ) {
        @tags = split( /\s*,\s*/, $tag_string );
    }
    $self->{tags} = \@tags;
}

# returns if this bookmark contains the given tag.
sub has_tag {
    my ( $self, $tag ) = @_;

    # FIXME we can do better than this, right?
    my @tags = $self->tags;
    foreach my $ltag ( @tags ) {
        if ( $ltag eq $tag ) {
            return 1;
        }
    }
    return 0;
}

# returns the security of this bookmark (public, private, usemask)
sub security {
    return $_[0]->{security};
}

# returns the comment
sub comment {
    return $_[0]->{comment};
}

# returns the last modified date of the bookmark
sub last_modified {
    return $_[0]->{'last_modified'};
}

# returns the created date of the bookmark
sub created {
    return $_[0]->{'created'};
}

# checks to see if this bookmark is visible to the current user
sub visible_to {
    my ( $self, $remote ) = @_;

    return 0 unless $self->user;
    
    # this is basically taken from Entry.pm
    my ($viewall, $viewsome) = (0, 0);
    if ( LJ::isu( $remote ) ) {
        $viewall = $remote->has_priv( 'canview', '*' );
        $viewsome = $viewall || $remote->has_priv( 'canview', 'suspended' );
    }

    # can see anything with viewall
    return 1 if $viewall;

    # can't see anything unless the journal is visible
    # unless you have viewsome. then, other restrictions apply
    unless ( $viewsome ) {
        return 0 if $self->user->is_inactive;

        # can't see anything by suspended users
        return 0 if $self->user->is_suspended;
    }

    # check if this is an entry/comment link, and if so, check if 
    # $remote can see that.
    if ( $self->type eq 'entry' ) {
        return 0 unless $self->entry;
        return 0 unless $self->entry->visible_to( $remote );
    } elsif ( $self->type eq 'comment' ) {
        return 0 unless $self->comment->visible_to( $remote );
    }
    
    return 1 if $self->{'security'} eq "public";
    
    # must be logged in otherwise
    return 0 unless $remote;

    my $userid   = int( $self->{userid} );
    my $remoteid = int( $remote->{userid} );
    
    # owners can always see their own.
    return 1 if $userid == $remoteid;

    # should be 'usemask' or 'private' security from here out, otherwise
    # assume it's something new and return 0
    return 0 unless $self->{security} eq "usemask" || $self->{security} eq "private";

    return 0 unless $remote->is_individual;

    if ( $self->security eq "private" ) {
        # other people can't read private on personal journals
        return 0 if $self->user->is_individual;

        # but community administrators can read private entries on communities
        return 1 if $self->user->is_community && $remote->can_manage( $self->user );

        # private entry on a community; we're not allowed to see this
        return 0;
    }

    if ( $self->security eq "usemask" ) {
        # check if it's a community and they're a member
        return 1 if $self->user->is_community &&
            $remote->member_of( $self->user );

        my $gmask = $self->user->trustmask( $remote );
        my $allowed = (int($gmask) & int($self->{allowmask}));
        return $allowed ? 1 : 0;  # no need to return matching mask
    }
}

# checks to see if this bookmark is editable by the current user
sub editable_by {
    my ( $self, $remote ) = @_;

    # for now, just return if the remote user is the owner of this
    # bookmark
    if ( $remote == $self->user ) {
        return 1;
    } else {
        return 0;
    }
}

# filters out tags that the given user doesn't have access to see
sub filter_tags {
    my ( $self, $remote ) = @_;

    #warn("checking tags");

    my @orig_tags = $self->tags;

    my $taginfo = $self->{taginfo};
    
    #warn("taginfo size = " . scalar keys %$taginfo);

    # this is basically taken from Entry.pm
    my ($viewall, $viewsome) = (0, 0);
    if ( LJ::isu( $remote ) ) {
        $viewall = $remote->has_priv( 'canview', '*' );
        $viewsome = $viewall || $remote->has_priv( 'canview', 'suspended' );
    }

    # can see anything with viewall
    return 1 if $viewall;

    # assumingly we've already determined that the bookmark itself is
    # visible, so we should just be checking the tag status.

    my @filtered_tags;

    #warn("taginfo size = " . scalar keys %$taginfo);
    my $check_tag = sub {
        my ( $tag, $security, $allowmask ) = @_;
        
        return 1 if $security eq "public";
        
        # must be logged in otherwise
        return 0 unless $remote;
        
        my $userid   = int( $self->{userid} );
        my $remoteid = int( $remote->{userid} );
        
        # owners can always see their own.
        return 1 if $userid == $remoteid;
        
        # should be 'usemask' or 'private' security from here out, otherwise
        # assume it's something new and return 0
        return 0 unless $security eq "usemask" || $security eq "private";
        
        return 0 unless $remote->is_individual;
        
        if ( $security eq "private" ) {
            # other people can't read private on personal journals
            return 0 if $self->user->is_individual;
            
            # but community administrators can read private entries on communities
            return 1 if $self->user->is_community && $remote->can_manage( $self->user );
            
            # private entry on a community; we're not allowed to see this
            return 0;
        }
        
        if ( $security eq "usemask" ) {
            # check if it's a community and they're a member
            return 1 if $self->user->is_community &&
                $remote->member_of( $self->user );
            
            my $gmask = $self->user->trustmask( $remote );
            my $allowed = (int($gmask) & int($allowmask));
            return $allowed ? 1 : 0;  # no need to return matching mask
        }
        
        return 1;
    };

    foreach my $tag ( keys %$taginfo ) {
        #warn("checking tag $tag");
        if ( $check_tag->( $tag, $taginfo->{$tag}->{security}, $taginfo->{$tag}->{allowmask} ) ) {
            #warn("adding tag $tag");
            push @filtered_tags, $tag;
        }
    }

    $self->{tags} = \@filtered_tags;
    $self->{tag_string} = join( ", ", @filtered_tags );

    return;
}

# clears the cache for the given item
sub _clear_associated_caches {
    my ( $self ) = @_;
    
    # FIXME
    #warn("clearing cache..");
    LJ::MemCache::delete( $self->_memcache_key( "q:userid:" . $self->{userid} ) );
    # a no-op by default; subclasses should override
}

1;

