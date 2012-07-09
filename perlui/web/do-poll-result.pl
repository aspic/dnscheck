#!/usr/bin/perl
#
# This script should basically do the same things as getResult.php.
# Poll for information from the database, and output that info as json
# to the ajax call from the user.
#
use strict;
use warnings;

# Load needed libraries
use DNSCheckWeb;
use DNSCheckWeb::Exceptions;
use CGI;
use JSON;
use Data::Validate::Domain qw(is_domain);

# Testing
use Data::Dumper;

# Constants for the valid types
use constant TYPES => {
	standard => "webgui",
	undelegated => "webgui-undelegated"
};

# Constants for feedback
use constant TEST_STARTED => "started";
use constant TEST_RUNNING => "running";
use constant TEST_FINISHED => "finished";
use constant TEST_ERROR => "error";

# Some important objects
my $dnscheck = DNSCheckWeb->new();
my $dbo = $dnscheck->get_dbo();
my $cgi = $dnscheck->get_cgi();

# Fetch parameters
my $domain = $cgi->param("domain");
my $source = TYPES->{$cgi->param("test")};
my $source_data = $cgi->param("parameters");

# Final json-string containing status and results
my $href_results = {
	domain => $domain
};

# Received domain name, check for running tests
eval {
	# Will do these tests for each poll.

	# Check if domain is valid
	if(!defined($domain) || length($domain) <= 2 || !is_domain($domain)) {
		DomainException->throw();
	}
	if(!defined($source)) {
		DomainException->throw();
	}

	# Source data can be undefined
	if(!defined($source_data)) {
		$source_data = '';
	}

	# Check if dispatcher is already testing this specific case
	my $running = $dbo->get_running_result($domain, $source, $source_data);

	if(@$running eq 0) {
		# No tests running, fire of new test.
		$dbo->start_check($domain, $source, $source_data);
		$href_results->{status} = TEST_STARTED;
	} elsif($running->[0][2] eq 'NO') {
		# Test for domain is running, but not finished
		$href_results->{status} = TEST_RUNNING;
	} else {
		# Finished test, set test_id
		$href_results->{test_id} = $running->[0][0];
		$href_results->{status} = TEST_FINISHED;
	}
};
# Catch errors
if (my $e = DomainException->caught()) {
	$href_results->{status} = TEST_ERROR;
	$href_results->{error_msg} = 'Error: ' . $e->description();
}

# Feed result back to browser
print $dnscheck->json_headers();
print encode_json $href_results;
