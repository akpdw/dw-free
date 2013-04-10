#!/usr/bin/perl
#
# Base class for DB objects
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

## Derived classes must implement the following methods:
## 
## _obj_props { }
## _skeleton { }
## _tablename { }
##
## _memcache_id                 { $_[0]->userid                 }
## _memcache_key_prefix         { "user"                        }
## _memcache_stored_props       { qw/$VERSION name age caps /   }
## _memcache_hashref_to_object  { LJ::User->new_from_row($_[0]) }
## _memcache_expires            { 24*3600                       }

package DW::BaseDbObj;
use strict;
use warnings;

use base 'LJ::MemCacheable';

# Object key column.
sub _key_column {
    return "id";
}

# Editable properties for the object. Defaults to all; may be overridden.
sub _editable_obj_props {
    return $_[0]->_obj_props;
}

# returns the WHERE clause for searching by ID
sub _where_by_id {
    return "WHERE " . $_[0]->_key_column . " = ?";
}

# returns the full object key for this object
sub _key {
    my $self = $_[0];
    return $self->{$self->_key_column};
}

sub _default_order_by {
    return "";
}

# DB utils
sub get_db_writer {
    return LJ::get_db_writer();
}
sub get_db_reader {
    return LJ::get_db_reader();
}


# create a new instance
sub instance {
    my ( $class, $id ) = @_;
    
    my $obj = $class->_skeleton( $id );
    return $obj;
}
*new = \&instance;

# instance methods
sub _absorb_row {
    my ($self, $row) = @_;

    # set the key
    $self->{$self->_key_column} = $row->{$self->_key_column};
    # and set all the properties
    for my $f ( $self->_obj_props ) {
        $self->{$f} = $row->{$f};
    }
    return $self;
}

# creates an new DbObj from a DB row
sub _new_from_row {
    my ($class, $row) = @_;
    die unless $row && $row->{$class->_key_column};
    my $self = $class->new( $row->{$class->_key_column} );
    $self->_absorb_row($row);
    return $self;
}

# creates a new instance
sub _create {
    my ( $class, $opts ) = @_;

    # validate the inputs first
    $class->validate( $opts );

    my $dbh = $class->get_db_writer();
    # new objectid
    #my $objid = $class->_get_next_id();

    # create and run the SQL
    my $entrystring =  join ( ',' , $class->_obj_props );
    my $qs = join( ', ', map { '?' } $class->_obj_props );
    my @values = map { $opts->{$_} }  $class->_obj_props;
    #warn("running INSERT INTO " . $class->_tablename . " ( $entrystring ) values ( $qs ), values=" . join( ",", @values));
    $dbh->do( "INSERT INTO " . $class->_tablename . " ( $entrystring ) values ( $qs )", undef, @values );
    
    LJ::throw($dbh->errstr) if $dbh->err;

    my $objid = $dbh->selectrow_array( "SELECT LAST_INSERT_ID()" );

    # now return the created object.
    my $obj = $class->_get_obj( $objid ) or LJ::throw("Error instantiating object");

    # clear the appropriate caches for this object
    $obj->_clear_associated_caches();

    return $obj;
}

# updates an existing instance
sub _update {
    my ( $self ) = @_;

    # validate the inputs first
    $self->validate( $self );

    my $dbh = $self->get_db_writer();

    # create and run the SQL
    my $qs = join( ', ', map { $_ . "=?" } $self->_obj_props );
    my @values = map { $self->{$_} }  $self->_obj_props;
    #warn ("updating: running UPDATE " . $self->_tablename . " set $qs WHERE " . $self->_key_column . "=? ; values = " . join (',', @values ));
    $dbh->do( "UPDATE " . $self->_tablename . " set $qs WHERE " . $self->_key_column . "=?", undef, @values, $self->id );
    
    LJ::throw($dbh->errstr) if $dbh->err;

    # now return the created object.
    my $obj = $self->by_id( $self->id ) or LJ::throw("Error instantiating object");

    # clear the cache.
    $self->_clear_cache();
    $self->_clear_associated_caches();

    return $obj;
}

# retrieves a single object by id, either from database or memcache
sub _get_obj {
    my ( $class, $objid ) = @_;

    my @keyarray = ( $objid );
    my @objarray = $class->_load_objs_from_keys( \@keyarray );
    if ( @objarray && scalar@objarray  ) {
        return $objarray[0];
    } else {
        return undef;
    }
}

# retrieves a set of objects by ids, either from database or memcache
# as appropriate
sub _load_objs_from_keys {
    my ( $class, $keys ) = @_;

    # return an empty array for an empty request
    if ( ! defined $keys || ! scalar @$keys ) {
        return ();
    }
    #warn("loading objs from keys ( " . join(",", @$keys ) . " ) ");

    # try from memcache first.  if we get all the results from memcache,
    # just return that.  otherwise, keep the misses and an id map for the
    # hits.
    my %memcache_objmap = ();
    my %db_objmap = ();
    my @memcache_misses = @$keys;
    if ( $class->memcache_enabled ) {
        #warn("loading from memcache");
        my $cached_value = $class->_load_batch_from_memcache( $keys );
        @memcache_misses = @{$cached_value->{misses}};
        %memcache_objmap = %{$cached_value->{objmap}};
    }

    if ( @memcache_misses ) {

        # if we got to here, then we need to query the db for at least a 
        # subset of the objects
        my $dbr = $class->get_db_reader();

        my $qs = join( ', ', map { '?' } @memcache_misses );
        
        #warn("running SELECT " . join ( ',' , ( $class->_key_column, $class->_obj_props ) ) . " FROM " . $class->_tablename . " WHERE " .  $class->_key_column . " IN ( $qs )");
        my $sth = $dbr->prepare( "SELECT " . join ( ',' , ( $class->_key_column, $class->_obj_props ) ) . " FROM " . $class->_tablename . " WHERE ".  $class->_key_column . " IN ( $qs )");
        $sth->execute( @memcache_misses );
        LJ::throw( $dbr->err ) if ( $dbr->err );
        
        # ok, now we create the objects from the db query
        my $obj;
        my @db_objs = ();
        while ( my $row = $sth->fetchrow_hashref ) {
            $obj = $class->_new_from_row( $row );

            #warn("created obj $obj");
            push @db_objs, $obj;
            $db_objmap{$obj->_key} = $obj;
        }

        # if we're using memcache, save the newly loaded objects to it.
        if ( $class->memcache_enabled ) {
            $class->_store_batch_to_memcache( \@db_objs );
        }
    }

    # stitch together the memcache results and the db results in the
    # original id order
    my @returnvalue = ();
    foreach my $key ( @$keys ) {
        push @returnvalue, $db_objmap{$key} || $memcache_objmap{$key};
    }
    return @returnvalue;
}

# updates this object's values from the provided object (or hash)
sub _copy_from_object {
    my ( $self, $source ) = @_;

    # go through each property available and 
    foreach my $prop ( $self->_editable_obj_props ) {
        warn("checking $prop");
        if ( exists $source->{$prop} ) {
            warn("setting $prop = " . $source->{$prop});
            $self->{$prop} = $source->{$prop};
        }
    }
}

# updates this object's values from the provided object (or hash).
sub copy_from_object {
    my ( $self, @args ) = @_;
    $self->_copy_from_object( @args );
}

# deletes this object.  may be overridden by subclasses
sub delete {
    return $_[0]->_delete();
}

# deletes this object
sub _delete {
    my ( $self ) = @_;
    
    my $dbh = $self->get_db_writer();
    #warn("deleting " . $self->_key);
    $dbh->do("DELETE FROM " . $self->_tablename . " " . $self->_where_by_id, 
           undef, $self->_key );

    # clear the cache.
    $self->_clear_cache();
    $self->_clear_associated_caches();

    return 1;
}


# clears the cache for the given item
sub _clear_cache {
    my ( $self ) = @_;

    $self->_remove_from_memcache( $self->id );
}

# clears the cache for the given item
sub _clear_associated_caches {
    my ( $self ) = @_;
    
    #my $data = $class->_load_from_memcache( "q:$field:$value" );
    #LJ::MemCache::delete( $class->_memcache_key( "q:userid:" . $self->{userid} ) );
    # a no-op by default; subclasses should override
}


# does the DB query for the appropriate values.
# FIXME ??? remove ??? use serach_ids instead ???
sub _search {
    my ( $class, $where_clause, @values ) = @_;

    my @objs;

    my $dbr = $class->get_db_reader();

    # note:  we're going ahead and load the full values
    my $sth = $dbr->prepare( "SELECT " . join ( ',' , ( $class->_key_column, $class->_obj_props ) ) . " FROM " . $class->_tablename . " " . $where_clause . " " . $class->_default_order_by );
    $sth->execute( @values );
    LJ::throw( $dbr->errstr ) if $dbr->err;

    my @objids;
    while ( my $row = $sth->fetchrow_hashref ) {
        my $obj = $class->_new_from_row( $row );
        push @objs, $obj;
    }
    return @objs;
}

# does the DB query for the appropriate values.
sub _search_ids {
    my ( $class, $where_clause, @values ) = @_;

    my $dbr = $class->get_db_reader();

    warn("running SELECT " . $class->_key_column . " FROM " . $class->_tablename . " " . $where_clause . " values - " . join (",", @values ) );
    my $ids = $dbr->selectcol_arrayref( "SELECT " . $class->_key_column . " FROM " . $class->_tablename . " " . $where_clause . " " . $class->_default_order_by, undef, @values );
    LJ::throw( $dbr->errstr ) if $dbr->err;
    
    warn("for search_ids, got $ids - scalar " . scalar @$ids . "; values " . join(",", @$ids ) );
    return $ids;
}

# returns all of the objects for the requested value
# NOTE:  $field should _never_ be user provided, since we're
# putting it directly in the query.
sub _all_items_by_value {
    my ( $class, $field, $value ) = @_;
   
    #warn("calling _all_items_by_value with $field, $value");
    my @ids = $class->_keys_by_value( $field, $value );
    #warn("all items by value:  got ids @ids - " . scalar @ids . " - " . join(",", @ids ));
    my @items = $class->_load_objs_from_keys( \@ids );
    #warn("all items by value:  got loaded objs from keys; got @items - " . scalar @items . " - " . join(",", @items));

    return @items;
}

# returns all of the ids for the requested value
# NOTE:  $field should _never_ be user provided, since we're
# putting it directly in the query.
sub _keys_by_value {
    my ( $class, $field, $value ) = @_;

    #warn("running _keys_by_value");
    my $ids;
    # see if we can get it from memcache
    my @objs;
    # see if we can get it from memcache
    if ( $class->memcache_query_enabled ) {
        #warn("running _keys_by_value for memcache.");
        $ids = $class->_load_keys( $field, $value );
        #warn("got $ids");
        if ( $ids && ref $ids eq 'ARRAY' && scalar @$ids > 1 ) {
            #warn("(not) returning ids - " . join(",", @$ids ) );
            return wantarray ? @$ids : $;
        }
    }

    # if we didn't get anything from memcache, try the database

    #warn("checking db");
    my $where_clause = "WHERE $field = ?";
    $ids = $class->_search_ids( $where_clause, $value );
    #warn("searched ids; got $ids - " . join(",", @$ids ));
    
    if ( $class->memcache_query_enabled ) {
        $class->_store_keys( $field, $value, $ids );
    }
    return wantarray ? @$ids : $ids;
}

# returns all of the ids that match the given search
sub _keys_by_search {
    my ( $class, $search ) = @_;

    warn("running _keys_by_search");
    my $ids;
    # see if we can get it from memcache
    my @objs;
    # see if we can get it from memcache
    #if ( $class->memcache_query_enabled ) {
        #warn("running _keys_by_value for memcache.");
        # $ids = $class->_load_keys( $field, $value );
        #warn("got $ids");
        #if ( $ids && ref $ids eq 'ARRAY' && scalar @$ids > 1 ) {
            #warn("(not) returning ids - " . join(",", @$ids ) );
        #    return wantarray ? @$ids : $;
        #}
    #}

    # if we didn't get anything from memcache, try the database

    warn("checking db");
    my $where_clause = "WHERE ";
    my @values = ();
    foreach my $searchterm ( @$search ) {
        #warn("adding searchterm");
        if ( $searchterm->{conjunction} ) {
            $where_clause .= $searchterm->{conjunction} . " ";
        }
        $where_clause .= $searchterm->{whereclause} . " ";
        if ( $searchterm->{values} ) {
            push @values, @$searchterm->{values};
        } elsif ( $searchterm->{value} ) {
            push @values, $searchterm->{value};
        }
        warn("whereclause = " . $where_clause);
    }
    $ids = $class->_search_ids( $where_clause, @values );
    warn("searched ids; got $ids - " . join(",", @$ids ));
    
    #if ( $class->memcache_query_enabled ) {
    #    $class->_store_keys( $field, $value, $ids );
    #}
    return wantarray ? @$ids : $ids;
}

# creates a search hash for a given key and value set. this version just
# does simple column comparisons; subclasses sould provide more complex
# examples
sub create_searchterm {
    my ( $class, $key, $comparator, @values ) = @_;
    # only allow registered columns
    if ( grep {$_ eq $key} $class->_obj_props ) {
        my $whereclause = " $key $comparator ";
        #warn ("using values @values");
        if ( scalar @values > 1 ) {
            $whereclause .= "(" . join( ', ', map { '?' } @values ) . ") ";
        } else {
            $whereclause .= "? ";
        }
        my $term = {
            column => $key,
            comparator => $comparator,
            whereclause => $whereclause,
        };
        if ( scalar @values > 1 ) {
            $term->{values} = \@values,
        } else {
            $term->{value} = $values[0];
        }
        return $term;
    }

    return 0;
}


# loads a list of items from memcache
sub _load_items {
    my ( $class, $field, $value ) = @_;

    #warn("running with field $field value $value");
    my $data = $class->_load_from_memcache( "q:$field:$value" );
    return unless $data && ref $data eq 'ARRAY';

    return $data;
}

# loads a list of keys from memcache
sub _load_keys {
    my ( $class, $field, $value ) = @_;

    my $id = "q:$field:$value";
    my $data = LJ::MemCache::get( $class->_memcache_key( $id ) );
    return unless $data && ref $data eq 'ARRAY';

    return $data;
}


# saves a list of keys to memcache
sub _store_keys {
    my ( $class, $field, $value, $keys ) = @_;

    my $id = "q:$field:$value";
    LJ::MemCache::set( $class->_memcache_key( $id ), $keys, $class->_memcache_expires);
}


sub _get_all {
    my ( $class ) = @_;

    # FIXME load from memcache

    #my $sth = $u->prepare( "SELECT * FROM " . $class->tablename . ";" );
    #$sth->execute($u->userid);
    #LJ::throw($u->errstr) if $u->err;
    return 0;
}

# returns the next available id
sub _get_next_id {
    my ( $class, $dbh ) = @_;
    
    return LJ::alloc_global_counter( $class->_globalcounter_id );
}

#validates the new object.  should be overridden by subclasses
sub validate {
    my ( $class, $opts ) = @_;

    return 1;
}

# returns the id of this object.
sub id {
    return $_[0]->{_obj_id};
}

# returns the object with the given id
sub by_id {
    my ( $class, $id ) = @_;

    return $class->_get_obj( $id );
}

#updates
sub update {
    my ( $self ) = @_;

    $self->_update();
}

# default memcache implementations

# use memcache for object storage
sub memcache_enabled { 1 }
# use memcache for search queries
sub memcache_query_enabled { 0 }

sub _memcache_id {
    return $_[0]->id;
}

# returns the properties stored in memcache for this object.
# default implementation:  returns the keys and properties of the object
sub _memcache_stored_props {
    my $class = $_[0];

    # first element of props is a VERSION
    # next - allowed object properties
    return (  $class->_memcache_version, $class->_key_column, $class->_obj_props );
}

# create a new object from a memcache row
sub _memcache_hashref_to_object {
    my ($class, $row) = @_;
    return $class->_new_from_row( $row );
}

# default expiration
sub _memcache_expires  { 24*3600 }

# loads an entire batch of ids from memcache.
sub _load_batch_from_memcache {
    my $class = shift;
    my $ids = shift;

    #warn("loading batch from memcache.");
    my @memcache_keys = ();
    my $keymap = {};
    for my $id ( @$ids ) {
        my $memcache_key = $class->_memcache_key( $id );
        #warn("adding memcache_key " . $memcache_key->[1] . " to request.");
        push @memcache_keys, $memcache_key->[1];
        #warn("setting keymap " . $memcache_key->[1] . " to $id.");
        $keymap->{$memcache_key->[1]} = $id;
    }
    my $mem = LJ::MemCache::get_multi( @memcache_keys );

    my ($version, @props) = $class->_memcache_stored_props;
    my @hits = ();
    my %misses = %$keymap;
    my @objects = ();
    my %objmap = ();
    while (my ($k, $v) = each %$mem) {
        #warn("checking key $k");
        if ( defined $v && ref $v eq 'ARRAY' ) {
            #warn("got hit for key $k for id " . $keymap->{$k});
            push @hits, $keymap->{$k};
            if ( $v->[0]==$version ) {
                my %hash;
                foreach my $i (0..$#props) {
                    $hash{ $props[$i] } = $v->[$i+1];
                }
                my $obj = $class->_memcache_hashref_to_object(\%hash);
                #warn("created object $obj");
                #warn("misses{key}=" .$misses{$k});
                push @objects, $obj;
                $objmap{$keymap->{$k}}=$obj;
                delete $misses{$k};
            }
        }
    }
    my @misses = values %misses;
    #warn("returning; hits=@hits, misses=@misses objects=@objects, objmap=" . %objmap );
    return {
        hits => \@hits,
        misses => \@misses,
        objects => \@objects,
        objmap => \%objmap,
    };
}

# save an entire batch of ids to memcache.
sub _store_batch_to_memcache {
    my $class = shift;
    my $objs = shift;

    # FIXME should do in batch
    for my $obj ( @$objs ) {
        $obj->_store_to_memcache();
    }
}
1;

