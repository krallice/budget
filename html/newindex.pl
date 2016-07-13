#!/usr/bin/perl

use strict;
no strict "subs";
use warnings;

use NavuaAO;
use CGI;
use HTML::Template;
use YAML::XS 'LoadFile';

# Load our YAML config (public + secret):
my $config = LoadFile('config.yaml');
my $secret_config = LoadFile('secret.yaml');

sub Main{

        # Define our Template Objects:
        my $head_template = HTML::Template->new( filename => "newhead.tmpl" );
        my $template = HTML::Template->new( filename => "newindex.tmpl", die_on_bad_params => 0 );
        my $tail_template = HTML::Template->new( filename => "newtail.tmpl" );

	my $navuaAO = NavuaAO->new(filename => "navua.db");

	$template->param( lastOffsetValue, $navuaAO->getLastOffsetValue() );
	$template->param( mortgageRemaining, $navuaAO->getMortgageRemainingPretty($config->{totalMortgage}) );

        # Output:
        print "Content-Type: text/html\n\n", $head_template->output, $template->output, $tail_template->output;
}

Main();
