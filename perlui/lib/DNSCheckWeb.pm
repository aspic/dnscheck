#!/usr/bin/perl
use strict;
use warnings;

package DNSCheckWeb;

use CGI;
use DBI;
use Template;
use File::Spec::Functions;
use Config::Any;

# Testing
use Data::Dumper;

# Custom modules
use DNSCheckWeb::DB;

# Config
my $cf_dbh;
my $config_hash;

sub new {
	my $class = shift;
	my $self = {};

	$self->{config} = config();

	bless $self, $class;
}

# Routine for reading the config (similar to the one in
# DNSCheck/Config.pm)
sub config {
	my $config = _get_with_path(
		_catfile('../', 'config.yaml')
    );
	return $config;
}

# Print headers and process the template.
sub render {
	my ($self, $file, $vars) = @_;

	# Setup template and prepare browser
	my $template = Template->new({INCLUDE_PATH => ['../templates']});
	print html_headers();

	# Adding some static variables
	$vars->{title} = 'Zone checker!';

	# Process the data
	$template->process($file, $vars) or die "Template rendering failed",
	$template->error(), "\n";
	exit;
}

# Returns the database object.
sub get_dbo {
	my $self = shift;

	unless (defined($self->{dbo})) {
		$self->{dbo} = DNSCheckWeb::DB->new($self->{config}->{dbi});
	}

	return $self->{dbo};
}

# Print headers to browser
sub html_headers {
	return CGI::header(-type=>'text/html; charset=utf-8', -expires=>'now');
}
sub json_headers {
	return CGI::header(-type=>'application/json; charset=utf-8', -expires=>'now');
}

# Build output tree.
sub build_tree {
	my ($self, $result) = @_;

	#
	# TODO: This "tree" includes HTML, should also have a raw tree?

	# De reference
	my @tests = @{ $result->{tests} };
	my @modules = ();
	my $indent = 0;
	my $result_status = 'OK'; # Presume that everything is ok

	foreach my $node (@tests) {

		# Assign some variables from the set
		my $module_id = $node->[0];
		my $parent_id = $node->[4];
		my $module = $modules[$module_id];
		my $class = $node->[6];
		my $type = $node->[7];
		my $caption = $node->[22];
		my $desc = $node->[23];

		# Construct caption given the arguments
		$caption = sprintf($caption, $node->[8], $node->[9],
		$node->[10], $node->[11], $node->[12], $node->[13], $node->[14],
		$node->[15], $node->[16], $node->[18]);

		# Start to build module
		my $child_module = {
			id => $module_id,
			caption => $caption,
			description => $desc,
			class => lc($class)
		};

		# Format for new class
		if($type=~ m/BEGIN$/) {
			$child_module->{tag_start} = '<ul><li>';
			#$child_module->{class} = "none";
			$indent++;
		} 

		# Format for end class
		if($type =~ m/END$/) {
			$child_module->{tag_start} = '</li><li>';
			$child_module->{tag_end} = '</ul>';
			#$child_module->{class} = "none";
			$indent--;
		}

		# Check whether we encountered an error
		if($child_module->{class} eq 'warn') {
			$result_status = $child_module->{class};
		} elsif($child_module->{class} eq 'error') {
			$result_status = $child_module->{class};
		}

		push @modules, $child_module;
	}

	# Assign new reference, and return
	$result->{tests} = \@modules;
	$result->{class} = $result_status;
	return $result;
}


# Resolves the given hostname to an A address
sub resolve {
	my ($self, $ns) = @_;
	
	# Results
	my $result = {
		hostname => $ns
	};

	my $res = Net::DNS::Resolver->new();
	my $query = $res->search($ns);

	if ($query) {
    	foreach my $rr ($query->answer) {
    		next unless $rr->type eq "A";
			$result->{addr} = $rr->address;
    	}
	}
	return $result;
}

# Only for internal use when loading config.
sub _catfile {
    my @tmp = grep {$_} @_;
    return catfile(@tmp);
}
sub _get_with_path {
    my @files = grep {$_} @_;

    my $cfg = Config::Any->load_files({
        files => \@files,
        use_ext => 1,
    });

    my ($c) = values %{$cfg->[0]};
    return $c;
}

1;
