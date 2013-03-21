#!/usr/bin/perl
#
# DW::Controller::Bookmarks
#
# Shows and manipulats bookmarks in the system.
#
# Author:
#      Allen Petersen
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Bookmarks;

use strict;
use warnings;
use DW::Routing;
use DW::Controller;
use DW::Bookmarks::Accessor;
use DW::Bookmarks::Bookmark;

use JSON;

DW::Routing->register_string( "/bookmarks", \&view_handler, user => 1, app => 1 );
DW::Routing->register_string( "/bookmarks/", \&view_handler, user => 1, app => 1 );
DW::Routing->register_string( "/bookmarks/recent", \&recent_handler, app => 1 );
DW::Routing->register_string( "/bookmarks/watch", \&watch_handler, user => 1 );
DW::Routing->register_string( "/bookmarks/network", \&network_handler, user => 1 );
DW::Routing->register_regex( "^/bookmarks/entry/(\\d+)\$", \&entry_handler, user => 1 );
DW::Routing->register_regex( "^/bookmarks/tag/([^/]+)\$", \&tag_handler, user => 1, app => 1 );
DW::Routing->register_regex( "/bookmarks/bookmark/([^/]+)", \&bookmark_handler, user => 1 );
DW::Routing->register_string( "/bookmarks/new", \&new_handler, app => 1, user => 1 );
DW::Routing->register_string( "/bookmarks/manage", \&manage_handler, user => 1 );
DW::Routing->register_string( "/bookmarks/post", \&post_handler, app => 1 );
DW::Routing->register_string( "/bookmarks/autocomplete/tag", \&autocomplete_handler, app => 1, formats => [ 'json' ] );

# views a set of bookmarks, either for a single user, a network, an extended
# network, or for the site.
sub view_handler {
    my ( $opts ) = @_;

    my $r = DW::Request->get;
    my $args = $r->get_args;

    my ( $ok, $rv ) = controller( anonymous => 1 );

    return ( $ok, $rv ) unless $ok;

    my $remote = $rv->{remote};
    my $user = LJ::load_user( $opts->username );

    if ( $user ) {
        # get the requested bookmarks
        my $after = $args->{after};
        my $before = $args->{before};
        warn("page_size = 10");
        my $page;
        if ( $args->{q} ) {
            my $search = search_from_querystring( $args->{q} );
            warn("search=$search");
            if ( @$search ) {
                push @$search, DW::Bookmarks::Accessor->create_searchterm( "userid", "=", $user->userid );

                my $ids = DW::Bookmarks::Accessor->_keys_by_search( $search );
                $page = DW::Bookmarks::Accessor->page_visible_by_remote( $ids, $remote, { after => $after, before => $before, page_size => 10 } );
            }
        }

        unless ( $page ) {
            warn("no page; using old version.");
            my $ids = DW::Bookmarks::Accessor->all_ids_for_user( $user );
            $page = DW::Bookmarks::Accessor->page_visible_by_remote( $ids, $remote, { after => $after, before => $before, page_size => 10 } );
        }

        # and get the user's tags
        my $taglist = DW::Bookmarks::Accessor->visible_tags_for_user( $user, $remote );
        my $editable = $remote ? $remote->can_manage( $user ) : 0;
        warn("editable=$editable ; remote=$remote ; user = $user ");
        my $vars = {
            remote => $remote,
            user => $user,
            bookmarks => $page->{items},
            page_before => $page->{page_before},
            page_after => $page->{page_after},
            taglist => $taglist,
            editable => $editable,
        };
        return render_template( 'bookmarks/list.tt', $vars );
    } else {
        # return the top bookamrks
        my $bookmarks = DW::Bookmarks::Accessor->popular_bookmarks( 10 );
        my $taglist = DW::Bookmarks::Accessor->top_tags(25);

        my $vars = {
            remote => $remote,
            bookmarks => $bookmarks,
            taglist => $taglist,
        };
        return render_template( 'bookmarks/list.tt', $vars );
    }
}

# views the most recent bookmarks for the system
sub recent_handler {
    my ( $opts ) = @_;
    my $r = DW::Request->get;
    my $args = $r->get_args;

    my ( $ok, $rv ) = controller( anonymous => 1 );

    return ( $ok, $rv ) unless $ok;

    my $remote = $rv->{remote};
    my $bookmarks = DW::Bookmarks::Accessor->recent_bookmarks();
    my $tags = DW::Bookmarks::Accessor->recent_tags( 10 );
    my $vars = {
        remote => $remote,
        bookmarks => $bookmarks,
        taglist => $tags,
    };
    warn("vars taglist = " . $vars->{taglist});
    return render_template( 'bookmarks/list.tt', $vars );
}

# views the most recent bookmarks of the given user's watch list
sub watch_handler {
    my ( $opts ) = @_;
    my $r = DW::Request->get;
    my $args = $r->get_args;

    my ( $ok, $rv ) = controller( anonymous => 1 );

    return ( $ok, $rv ) unless $ok;

    my $remote = $rv->{remote};
    my $user = LJ::load_user( $opts->username );
    if ( $user ) {
        my @bookmarks = DW::Bookmarks::Accessor->by_watch_list( $user, $remote );
        my $vars = {
            remote => $remote,
            bookmarks => \@bookmarks
        };
        return render_template( 'bookmarks/list.tt', $vars );
    }

}

# views the most recent bookmarks of the user's extended network
sub network_handler {
    my ( $opts ) = @_;
    my $r = DW::Request->get;
    my $args = $r->get_args;

    my ( $ok, $rv ) = controller( anonymous => 1 );

    return ( $ok, $rv ) unless $ok;

    my $remote = $rv->{remote};
    my $user = LJ::load_user( $opts->username );
    if ( $user ) {
        
        my @bookmarks = DW::Bookmarks::Accessor->visible_by_user( $user, $remote );
        my $vars = {
            remote => $remote,
            bookmarks => \@bookmarks
        };
        return render_template( 'bookmarks/list.tt', $vars );
    } else {
        my @bookmarks = DW::Bookmarks::Accessor->top_bookmarks;

        my $vars = {
            remote => $remote,
            bookmarks => \@bookmarks
        };
        return render_template( 'bookmarks/list.tt', $vars );
    }
}

# handles both the new bookmark form and the form submit.
sub new_handler {
    my $r = DW::Request->get;
    
    my ( $args, $errors );
    
    my ( $ok, $rv ) = controller( anonymous => 0 );
    return ( $ok, $rv ) unless $ok;

    # if form submit, handle
    if ( $r->did_post ) {
        # FIXME should allow for community bookmarks
        $args = $r->post_args;
        my $remote = $rv->{remote};
        
        my $tag = $args->{tag};
        my $type = $args->{"bookmark_type"};
        
        warn ("running create.");
        my $result = eval { DW::Bookmarks::Bookmark->create( $remote, $args ); };
        if ( $result ) {
            warn("successful create!");
            if ( $args->{ajax} eq "true" ) {
                warn("returning success obj");
                return ("{ success: 1 }");
            } else {
                warn("returning redirect to " . $remote->journal_base . "/bookmarks");
                return $r->redirect( $remote->journal_base . "/bookmarks" );
            }
        } else {
            warn("errors=$@");
            $errors = $@;
        }
    }
    
    # if we've gotten an error from the post, note it here.
    $args = $args || $r->get_args;
    
    $args->{type} = 'url' unless $args->{type};
    $args->{security} = 'public' unless $args->{security};
    warn("type=" . $args->{type} . "; security = " . $args->{security});

    my $remote = $rv->{remote};
    my $vars = {
        remote => $remote,
        bookmark => $args,
        error_list => $errors,
        fragment => $args->{fragment},
    };
    warn("returning template.");
    if ( $args->{bookmarklet} ) {
        #return  DW::Template->render_template( 'bookmarks/bookmarklet_add.tt', $vars, { fragment => 1 } );
        return  DW::Template->render_template( 'bookmarks/bookmarklet_add.tt', $vars, { no_sitescheme => 1 } );
    } else {
        return DW::Template->render_template( 'bookmarks/add.tt', $vars, { fragment => $args->{fragment} } );
    }
}

# FIXME not here yet
sub bookmark_handler {
    my $r = DW::Request->get;
    return $r->redirect( "/bookmarks" );
}

# Displays the tags for a particular entry
sub entry_handler {
    my ( $opts, $ditemid ) = @_;

    my $r = DW::Request->get;
    my $args = $r->get_args;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    
    return ( $ok, $rv ) unless $ok;

    my $remote = $rv->{remote};

    my $user = LJ::load_user( $opts->username );
    if ( $user ) {
        my $entry = LJ::Entry->new( $user, ditemid => $ditemid );
        if ( $entry && $entry->visible_to( $remote ) ) {
            my @bookmarks = DW::Bookmarks::Accessor->visible_by_entry( $entry, $remote );
            if ( scalar @bookmarks ) {
                my $vars = {
                    remote => $remote,
                    bookmarks => \@bookmarks,
                    entry => $entry,
                };
                return render_template( 'bookmarks/for_entry.tt', $vars );
            }
        }
    }
    # FIXME return error
    return $r->redirect( "/bookmarks" );
}

# Display content with the given tag
sub tag_handler {
    my ( $opts, $tag ) = @_;

    warn("running tag handler");
    my $r = DW::Request->get;
    my $args = $r->get_args;

    my ( $ok, $rv ) = controller( anonymous => 1 );

    return ( $ok, $rv ) unless $ok;

    warn("still running tag handler");
    my $remote = $rv->{remote};
    my $user = LJ::load_user( $opts->username );

    if ( $user ) {
        warn("in user context");
        my @bookmarks = DW::Bookmarks::Accessor->visible_by_user_tag( $user, $tag, $remote );
        my $vars = {
            remote => $remote,
            bookmarks => \@bookmarks
        };
        return render_template( 'bookmarks/list.tt', $vars );
    } else {
        warn("not in user context");
        my @bookmarks = DW::Bookmarks::Accessor->by_tag( $tag );

        #warn("returning " . scalar @bookmarks . " bookmarks");
        my $vars = {
            remote => $remote,
            bookmarks => \@bookmarks
        };
        return render_template( 'bookmarks/list.tt', $vars );
    }
}

# Tries autocomplete
sub autocomplete_handler {
    my ( $opts, $tag ) = @_;

    warn("running autocomplete handler");
    my $r = DW::Request->get;
    my $args = $r->get_args;

    my ( $ok, $rv ) = controller( anonymous => 1 );

    return ( $ok, $rv ) unless $ok;

    warn("still running autocomplete handler");
    my $term = $args->{term};
    warn("using term $term");
    my $format = $opts->format;
    my @results = ( $term . "foo", $term . "bar", $term . "baz" );
    if ( $format eq 'json' ) {
        warn("requesting json");
        # this prints out the menu navigation as JSON and returns
        $r->print( JSON::objToJson( \@results ) );
        return $r->OK;
    } else {
        warn("not requesting json, but returning it anyway");
        # this prints out the menu navigation as JSON and returns
        $r->print( JSON::objToJson( \@results ) );
        return $r->OK;
    }
}

# creates a new message containing the given bookmarks and redirects
# to an editor
sub post_handler {
    my ( $opts, $tag ) = @_;

    my $r = DW::Request->get;
    my $args = $r->get_args;

    my ( $ok, $rv ) = controller( anonymous => 1 );

    return ( $ok, $rv ) unless $ok;

    my $remote = $rv->{remote};

    my @ids = $args->get_all( "ids" );
    warn("ids=@ids");
    foreach my $id ( @ids ) {
        warn("id=$id");
    }
    
    my $bookmarks = DW::Bookmarks::Accessor->visible_by_ids( $remote, \@ids );

    my $vars = {
        bookmarks => $bookmarks,
    };
    my $text = DW::Template->template_string( 'bookmarks/post.tt', $vars, { fragment => 1 } );
    #warn("text=$text");
    #return render_template( 'bookmarks/list.tt', $vars, { fragment => 1 } );
    #my $text = render_template( 'bookmarks/list.tt', $vars, { fragment => 1 } );
    #warn("text=$text");
    return $r->redirect( "/update?subject=Bookmarks&event=" . LJ::eurl( $text ) );
}

#
sub render_template {
    my ( $template, $vars ) = @_;
    $vars->{bmark_main_page} = $template;
    return DW::Template->render_template( "bookmarks/page_template.tt", $vars );
}

# creates a search hash from a query string
sub search_from_querystring {
    my ( $queryarg ) = @_;

    my @search;
    my @query_split = split( ',', $queryarg );

    foreach my $query ( @query_split ) {
        warn("checking query '$query'");
        my ( $key, $value ) = split( ':', $query );
        if ( $key eq 'security' && $value eq 'locked' ) {
            $value = 'usemask';
        }
        my $term = DW::Bookmarks::Accessor->create_searchterm( $key, '=', $value );
        $term->{conjunction} = scalar @search ? 'AND' : '';
        push @search, $term;
    }

    warn("returning " . scalar \@search . " searchterms from querystring.");
    return \@search;

}

1;
