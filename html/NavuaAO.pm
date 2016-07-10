#!/usr/bin/perl

# File: NavuaAO.pm
# Perl package/class for interfacing with navua.db. Bit of a practise/learning curve with the Data Access Object (DAO) design pattern.
# Replacing code that directly interfaced with the database

package NavuaAO;

use strict;
use warnings;
use Carp;

use DBI;

# Init our Navua Access Object: 
sub new {

	# Init ourselves:
	my $class = shift;
	my $self = { @_ };
	# Ensure filename for DB is given by caller:
	croak "Bad Arguments" unless defined $self->{filename};

	$self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}");

	return bless $self, $class;
}

# Return our database name:
sub getFilename {
	my $self = shift;
	return "$self->{filename}";
}

# Get the First $ value placed into offset:
sub getFirstOffsetValue {

	my $self = shift;
        my $sqlQuery = $self->{dbh}->prepare("SELECT amount FROM payments LIMIT 1");
        $sqlQuery->execute();

	my $value = "";
        while ( my $row = $sqlQuery->fetchrow_hashref ) {
		$value = $row->{amount};
	}
	
	return $value;
}

# Get the First $ value placed into offset:
sub getLastOffsetValue {

	my $self = shift;
        my $sqlQuery = $self->{dbh}->prepare("SELECT amount FROM payments ORDER BY date DESC LIMIT 1");
        $sqlQuery->execute();

	my $value = "";
        while ( my $row = $sqlQuery->fetchrow_hashref ) {
		$value = $row->{amount};
	}
	
	return $value;
}

1;
