#!/bin/sh

exec "$COMMANDER_HOME/bin/ec-perl" -x "$0" "${@}"

#!perl

use strict;
use ElectricCommander;
use CGI;
use JSON;
use MIME::Base64;
use URI::Escape;
use Data::Dumper;

$| = 1;

# Create a single instance of the Perl access to ElectricCommander
my $ec = new ElectricCommander();
my $q = CGI->new;

my $code = $q->param('code');

my $raw_state = $q->param('state');
# print "State: $raw_state\n";

my $state = decode_json(decode_base64($raw_state));

my $job_id = $state->{jobId};

$ec->setProperty({propertyName => '/myJob/cb_auth_code', value => $code, jobId => $job_id});

print $q->redirect("/commander/link/jobDetails/jobs/$job_id");

