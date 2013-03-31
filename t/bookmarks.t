# -*-perl-*-
use strict;

use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN {
    require 'ljlib.pl'; 
#    require "$ENV{LJHOME}/cgi-bin/LJ/Directories.pm";
}
use LJ::Test qw ( temp_user temp_comm );
#use LJ::Directories;

use DW::Bookmarks::Accessor;
use DW::Bookmarks::Bookmark;
use DW::Bookmarks::Preference;

plan tests => 65;

# set up users and entries

my $u1 = temp_user();
my $u2 = temp_user();
my $u3 = temp_user();
my $c1 = temp_comm();

ok( $c1->is_community, 'c1 is community' );

# clear all bookmarks and preferences for these users, in case we're 
# re-using ids.
foreach my $u ( ( $u1, $u2, $u3, $c1 ) ) {
    foreach my $bookmark ( DW::Bookmarks::Accessor->all_for_user( $u ) ) {
        $bookmark->delete();
    }
    foreach my $pref ( DW::Bookmarks::Preference->all_for_user( $u ) ) {
        $pref->delete();
    }
}

my $args = {
    tag_string => 'tag1, tag2',
    title => 'my title',
    type => 'url',
    security => 'public',
    url => 'http://www.dreamwidth.org/',
    des => 'test des', 
};

# tests basic creation of bookmarks
# create bookmarks with each option
my $bookmark = DW::Bookmarks::Bookmark->create( $u1, $args );
ok ( $bookmark, 'bookmark created' );
is ( $bookmark->url, $args->{url}, 'url matches' );
is ( $bookmark->title, $args->{title}, 'title matches' );
my @bookmark_tags = $bookmark->tags;
is ( $bookmark_tags[0], 'tag1', 'first tag matches' );
is ( $bookmark_tags[1], 'tag2', 'second tag matches' );
is ( $bookmark->tag_string, 'tag1, tag2', 'tag_string matches');

# tests basic read
my @bookmarks = DW::Bookmarks::Accessor->all_for_user( $u1 );
is( scalar @bookmarks, 1, 'bookmark count' );

# test create and read back
my $bookmark2 = DW::Bookmarks::Bookmark->create( $u1, $args );
my @bookmarks = DW::Bookmarks::Accessor->all_for_user( $u1 );
is( scalar @bookmarks, 2, 'bookmark count after add' );

# tests basic delete
my @bookmarks = DW::Bookmarks::Accessor->all_for_user( $u1 );
foreach my $bookmark ( @bookmarks ) {
    $bookmark->delete();
}
@bookmarks = DW::Bookmarks::Accessor->all_for_user( $u1 );
is( scalar @bookmarks, 0, 'bookmark count after delete' );

# test update
my $bookmark3 = DW::Bookmarks::Bookmark->create( $u1, $args );
$bookmark3->{comment} = "This is a new, updated comment.";
$bookmark3->update();
my $bookmark3_updated = DW::Bookmarks::Accessor->by_id( $bookmark3->id );
is( "This is a new, updated comment.", $bookmark3_updated->comment, "Comment update succeeded." );

# update by source object
my $orig_created = $bookmark3_updated->created;
$bookmark3_updated->copy_from_object( { comment => "comment 3", created => 0, tag_string => "tag1,tag2,tag19" } );
$bookmark3_updated->update();
$bookmark3_updated = DW::Bookmarks::Accessor->by_id( $bookmark3->id );
is( "comment 3", $bookmark3_updated->comment, "Comment update succeeded via object copy." );
is( "tag1, tag2, tag19", $bookmark3_updated->tag_string, "Tags update succeeded via object copy." );
is( $orig_created, $bookmark3_updated->created, "Created correcly not updated by object copy" );


# ok, testing some functionality now

# create some entries

my $e_public = $u1->t_post_fake_entry();
my $e_private = $u1->t_post_fake_entry( security => 'private' );
isnt( $e_private->visible_to( $u2 ), 1, "private entry not visible" );

my $e_locked = $u1->t_post_fake_entry( security => 'friends' );
# create some bookmarks
my $b_pub = DW::Bookmarks::Bookmark->create( $u1, { tag_string => 'tag1', title => 'test title', type => 'url', security => 'public',url => 'http://www.dreamwidth.org/', des => 'test des' });
is( $b_pub->visible_to( $u2 ), 1, "public visible" );


my $b_pubentry = DW::Bookmarks::Bookmark->create( $u1, { tag_string => 'tag1', title => 'test title', type => 'entry', security => 'public',ditemid => $e_public->ditemid, journal => $e_public->journal->username, des => 'test des'});
is( $b_pubentry->url, $e_public->url, "entry url matches" );
is( $b_pubentry->visible_to( $u2 ), 1, "entry visible" );

my $b_priv = DW::Bookmarks::Bookmark->create( $u1, { tag_string => 'tag2', title => 'test title', type => 'entry', security => 'private',ditemid => $e_public->ditemid, journalid => $e_public->journalid, des => 'test des'});
is( $b_priv->visible_to( $u1 ), 1, "private bookmark visible to poster" );
isnt( $b_priv->visible_to( $u2 ), 1, "private bookmark not visible" );

my $b_pub_priv = DW::Bookmarks::Bookmark->create( $u1, { tag_string => 'tag3', title => 'test title', type => 'entry', security => 'public',ditemid => $e_private->ditemid, journalid => $e_private->journalid, des => 'test des'});
isnt( $b_pub_priv->visible_to( $u2 ), 1, "public bookmark of private entry not visible" );

# test validation
my $create_test;
# missing user
my $create_test = eval { DW::Bookmarks::Bookmark->create( 0, { tag_string => 'tag3', title => 'test title', type => 'entry', security => 'public',ditemid => $e_private->ditemid, journalid => $e_private->journalid, des => 'test des'}) };
ok( $@, "error creating with invalid user" );
ok( ! $create_test, "error creating with invalid user" );

# no tags
$create_test = 0;
$create_test = eval { DW::Bookmarks::Bookmark->create( $u1, {  title => 'test title', type => 'entry', security => 'public',ditemid => $e_private->ditemid, journalid => $e_private->journalid, des => 'test des'}) };
ok( ! $@, "success creating with no tag" );
ok( $create_test, "success creating with no tag" );

# no type
$create_test = 0;
$create_test = eval { DW::Bookmarks::Bookmark->create( $u1, { tag_string => 'tag3',  security => 'public',ditemid => $e_private->ditemid, journalid => $e_private->journalid, des => 'test des'}) };
ok( $@, "error creating with no type" );
ok( ! $create_test, "error creating with no type" );

# invalid type
$create_test = 0;
$create_test = eval { DW::Bookmarks::Bookmark->create( $u1, { tag_string => 'tag3',  title => 'test title', type => 'invalid', security => 'public',ditemid => $e_private->ditemid, journalid => $e_private->journalid, des => 'test des'}) };
ok( $@, "error creating with no type" );
ok( ! $create_test, "error creating with no type" );

# no security
$create_test = 0;
$create_test = eval { DW::Bookmarks::Bookmark->create( $u1, { tag_string => 'tag3',  title => 'test title', type => 'entry', ditemid => $e_private->ditemid, journalid => $e_private->journalid, des => 'test des'}) };
ok( $@, "error creating with no security" );
ok( ! $create_test, "error creating with no security" );

# invalid entry
$create_test = 0;
$create_test = eval { DW::Bookmarks::Bookmark->create( $u1, { tag_string => 'tag3',  title => 'test title', type => 'entry', security => 'public',ditemid => 14, journalid => $e_private->journalid, des => 'test des'}) };
ok( $@, "error creating with invalid entry" );
ok( ! $create_test, "error creating with invalid entry" );

# not visible entry
$create_test = 0;
$create_test = eval { DW::Bookmarks::Bookmark->create( $u2, { tag_string => 'tag3',  title => 'test title', type => 'entry', security => 'public',ditemid => $e_private->ditemid, journalid => $e_private->journalid, des => 'test des'}) };
ok( $@, "error creating with not visible entry" );
ok( ! $create_test, "error creating with not visible entry" );

# url type, no url
$create_test = 0;
$create_test = eval { DW::Bookmarks::Bookmark->create( $u1, { tag_string => 'tag3',  title => 'test title', type => 'url', security => 'public', des => 'test des'}) };
ok( $@, "error creating with missing url" );
ok( ! $create_test, "error creating with missing url" );

# no title
$create_test = 0;
$create_test = eval { DW::Bookmarks::Bookmark->create( $u1, { tag_string => 'tag3',  security => 'public',ditemid => $e_private->ditemid, journalid => $e_private->journalid, des => 'test des'}) };
ok( $@, "error creating with no title" );
ok( ! $create_test, "error creating with no title" );



## BOOKMARK PREFERENCES ##

# create bookmark preference
my $pref_tag = 'preftesttag';
my $pref_args = { u=>$u1, tag => $pref_tag, security => 'private', comment => 'private tag!' };
my $pref = DW::Bookmarks::Preference->create( $pref_args );
ok ( $pref, 'pref created' );
is ( $pref->security, $pref_args->{security}, 'security matches' );
is ( $pref->tag, $pref_args->{tag}, 'tag matches' );
is ( $pref->comment, $pref_args->{comment}, 'comment matches' );

# create bookmark with (currently) private tag
$args = {
    tag_string => "$pref_tag, pubtag",
    title => 'test title', type => 'url',
    security => 'public',
    url => 'http://www.dreamwidth.org/',
    des => 'test des', 
};

$bookmark = DW::Bookmarks::Bookmark->create( $u1, $args );

# now load it as another user

$bookmark = DW::Bookmarks::Accessor->visible_by_id( $bookmark->user, $bookmark->id, $u2 );
is ( scalar $bookmark->tags, 1, 'tag filtered by preference override' );

# update preference
$pref = DW::Bookmarks::Preference->for_tag( $u1, $pref_tag );

$pref->set_security( "public" );
$pref->update();

$pref = DW::Bookmarks::Preference->for_tag( $u1, $pref_tag );
is( $pref->security, 'public', 'set preference security' );

$bookmark = DW::Bookmarks::Accessor->visible_by_id( $bookmark->user, $bookmark->id, $u2 );
is ( scalar $bookmark->tags, 2, 'preference change unfilters tag' );

# pages
is( scalar DW::Bookmarks::Accessor->visible_by_user( $u1, $u1 ), 6, "visible_by_user count, self" );
is( DW::Bookmarks::Accessor->visible_by_user( $u1, $u2 ), 4, "visible_by_user count, other" );

# by entry
my $b_pubentry2 = DW::Bookmarks::Bookmark->create( $u2, { tag_string => 'tag5', title => 'test title', type => 'entry', security => 'public', ditemid => $e_public->ditemid, journal => $e_public->journal->username, des => 'test des again'});

my @for_epublic = DW::Bookmarks::Accessor->visible_by_entry( $e_public, $u1 );
is ( scalar @for_epublic, 3, "visible for entry count" );
my $all_match = 1;
foreach my $b_for_ep ( @for_epublic ) {
    $all_match = 0 unless ( $b_for_ep->type eq 'entry' &&  $b_for_ep->ditemid == $e_public->ditemid &&  $b_for_ep->journalid == $e_public->journal->{userid} );
}
ok ( $all_match, "all bookmarks for visible_for_entry are for the entry" );

# one of the earlier entries was private.
my @for_epublic_u2 = DW::Bookmarks::Accessor->visible_by_entry( $e_public, $u2 );
is ( scalar @for_epublic_u2, 2, "visible for entry count, filtering private" );

# list bookmarks by tag
# FIXME
my @tag_bookmarks = DW::Bookmarks::Accessor->by_tag( "tag1" );
ok( @tag_bookmarks, "bookmarks loaded by_tag");

if ( scalar @tag_bookmarks > 10 ) {
    @tag_bookmarks = @tag_bookmarks[0,9];
}
my $all_valid = 1;
foreach my $tag_bookmark ( @tag_bookmarks ) {
    if ( $all_valid ) { 
        my $match = 0;
        my @tb_tags = $tag_bookmark->tags;
        foreach my $tb_tag ( @tb_tags ) {
            if ( ! $match ) {
                $match = ( $tb_tag eq "tag1" );
            }
        }
        if ( ! $match ) {
            $all_valid = 0;
        }
    }
}
is( $all_valid, 1, "all bookmarks returned by by_tag have the correct tag" );

# tag list test
my $tag_list = DW::Bookmarks::Accessor->visible_tags_for_user( $u1, $u1 );

is( scalar @$tag_list, 6, "count of all tags for user");
# go through tags and find tag1 and check its usage count
foreach my $tag ( @$tag_list ) {
    if ( $tag->{tag} eq 'tag1' ) {
        is( $tag->{tagcount}, 3, "count of uses of tag1 for user");
    }
}

my $pubtag_list = DW::Bookmarks::Accessor->visible_tags_for_user( $u1, undef );

is( scalar @$pubtag_list, 6, "count of public tags for user");
foreach my $tag ( @$pubtag_list ) {
    if ( $tag->{tag} eq 'tag2' ) {
        is( $tag->{tagcount}, 1, "count of public uses of tag2 for user");
    }
}

# list popular bookmarks
# FIXME in theory, we should know what bookmarks are popular in our test
# DB and then make sure we return the correct values, but....
my $popular = DW::Bookmarks::Accessor->popular_bookmarks();
ok( ( $popular && ref $popular eq 'ARRAY' && scalar @$popular > 1 ), "popular bookmarks returned valid values" );
warn("popular bookmarks returned " . @$popular );
my $previous = -1;
my $inorder = 1;
foreach my $popentry ( @$popular ) {
    if ( $previous != -1 ) {
        if ( $popentry->{count} > $previous ) {
            $inorder = 0;
        }
    }
    $previous = $popentry->{count};
}
ok( $inorder, "Popular bookmarks returned in order" );

# add tags
DW::Bookmarks::Bookmark->create( $u1, { tag_string => 'tag5', title => 'test title', type => 'entry', security => 'public', ditemid => $e_public->ditemid, journal => $e_public->journal->username, des => 'test des again'});
DW::Bookmarks::Bookmark->create( $u1, { tag_string => 'tag5', title => 'test title', type => 'url', security => 'public', url => 'http://www.dreamwidth.org/', des => 'test des again'});
DW::Bookmarks::Bookmark->create( $u1, { tag_string => 'tag6', title => 'test title', type => 'url', security => 'public', url => 'http://www.dreamwidth.org/index.html', des => 'test des again'});

my @addto = DW::Bookmarks::Accessor->all_for_user( $u1 );
my @addtags = ( 'addme1', 'addme2', 'addme3' );
DW::Bookmarks::Accessor->add_tags( \@addto, \@addtags, $u1 );
my @added = DW::Bookmarks::Accessor->all_for_user( $u1 );
my $all_added = 1;
foreach my $added_bookmark ( @added ) {
    foreach my $added_tag ( qw/addme1 addme2 addme3/ ) {
        unless ( $added_bookmark->has_tag( $added_tag ) ) {
            $all_added = 0;
        }
    }
}
ok( $all_added, "Added multiple tags to multiple bookmarks." );

my @removefrom = DW::Bookmarks::Accessor->all_for_user( $u1 );
my @removetags = ( 'addme1', 'addme2' );
DW::Bookmarks::Accessor->remove_tags( \@removefrom, \@removetags, $u1 );
my @removed = DW::Bookmarks::Accessor->all_for_user( $u1 );
my $all_removed = 1;
foreach my $removed_bookmark ( @removed ) {
    foreach my $removed_tag ( qw/addme1 addme2/ ) {
        if ( $removed_bookmark->has_tag( $removed_tag ) ) {
            $all_removed = 0;
        }
    }
}
ok( $all_removed, "Removed multiple tags from multiple bookmarks." );

my @updatesecurity = DW::Bookmarks::Accessor->all_for_user( $u1 );
DW::Bookmarks::Accessor->update_security( \@updatesecurity, 'usemask', 1, $u1 );
my @secupdated = DW::Bookmarks::Accessor->all_for_user( $u1 );
my $all_updated = 1;
foreach my $updated_bmark ( @secupdated ) {
    unless ( $updated_bmark->security eq 'usemask' || $updated_bmark->allowmask != 1 ) {
        $all_updated = 0;
    }
}
ok( $all_updated, "Updated security for multiple bookmarks." );

# search options
my $u1_search = DW::Bookmarks::Accessor->create_searchterm( "userid", "=", $u1->userid );
$u1_search->{conjunction} = 'AND';
my $private_search = DW::Bookmarks::Accessor->create_searchterm( "security", "=", "private" );
my $public_search = DW::Bookmarks::Accessor->create_searchterm( "security", "=", "public" );
my $locked_search = DW::Bookmarks::Accessor->create_searchterm( "security", "=", "usemask" );

my @search = ( $public_search, $u1_search );
my $public_u1 = DW::Bookmarks::Accessor->_keys_by_search( \@search );
my $page = DW::Bookmarks::Accessor->page_visible_by_remote( $public_u1, $u1, { page_size => 10 } );
my $all_public = 1;

foreach my $page_bmk ( @{$page->{items}} ) {
    if ( $page_bmk->security ne 'public' ) {
        $all_public = 0;
    }
}
ok( $all_public, "public search returned public bookmarks only" );

@search = ( $locked_search, $u1_search );
my $locked_u1 = DW::Bookmarks::Accessor->_keys_by_search( \@search );
$page = DW::Bookmarks::Accessor->page_visible_by_remote( $public_u1, $u1, { page_size => 10 } );
my $all_locked = 1;

foreach my $page_bmk ( @{$page->{items}} ) {
    if ( $page_bmk->security ne 'usemask' ) {
        $all_locked = 0;
    }
}
ok( $all_locked, "locked search returned locked bookmarks only" );

@search = ( $private_search, $u1_search );
my $private_u1 = DW::Bookmarks::Accessor->_keys_by_search( \@search );
$page = DW::Bookmarks::Accessor->page_visible_by_remote( $private_u1, $u1, { page_size => 10 } );
my $all_private = 1;

foreach my $page_bmk ( @{$page->{items}} ) {
    if ( $page_bmk->security ne 'private' ) {
        $all_private = 0;
    }
}
ok( $all_private, "private search returned private bookmarks only" );

# search for your bookmarks with a specific tag
# search for friends' bookmarks with a specific tag
# search for anyone's bookmarks with a specific tag


# list top bookmarks
# FIXME
#my @top_bookmarks = DW::Bookmarks::Accessor->top_bookmarks( 10 );
#is ( scalar @top_bookmarks, 10, "top bookmarks count is correct." );

# match tags
#my $b_pubentry2 = DW::Bookmarks::Bookmark->create( $u2, { tag_string => 'tag5', title => 'test title', type => 'entry', security => 'public', ditemid => $e_public->ditemid, journal => $e_public->journal->username, des => 'test des again'});

# FIXME
# my @matched = DW::Bookmarks::Accessor->match_tags( $u2, 't' );


# visibility
# public, access, specific list, private url
# -- test no user, positive, and negative
# public, access, specific list, private entries/comments
# -- test no user, positive, and negative
# lists for user (make sure counts, etc. are correct)

#tag lists
# get list of own tags
# get list of popular tags

#tag cloud

#top tags

#bookmarks for entries

