#!/usr/bin/perl
#
# Copyright (c) 2017 Pivotal Software, Inc.  All rights reserved.
#
# This script searches and replaces the installation paths specified by:
#
#   --srcdir=path or string to be replaced 
#   --dstdir=/path/to/destination/installation
#
# Pivotal Web Server patch distributions include two patterns to replace:
#
#   @@ PRODUCT_ROOT @@    --  the product root path
#   @@ SERVER_ROOT @@	  --  one /path-to-root/servers/{instance}
#                             to be used for individual server instances
#
# Invoking this script from the product root path will default the
# @@ PRODUCT_ROOT @@ to the current working directory
#
# NOTE: the whitespace within the @@ ... @@ patterns above is to prevent
# this script from modifying it's own documentation - do not include the
# spaces when specifying these patterns.

use Getopt::Long;
use File::Find;
use Cwd;

my $DESTDIR   = Cwd::cwd;
my $SUBSTDIR  = '@@PRODUCT'.'_ROOT@@';

GetOptions('srcdir=s'   => \$SUBSTDIR,
	   'dstdir=s'   => \$DESTDIR);

if (length($DESTDIR) < 2) {
    print "Error; invalid --dstdir was given, or could not be determined by Cwd::cwd\n";
    exit 1;
}

if (length($SUBSTDIR) < 2) {
    print "Error; invalid --srcdir was given\n";
    exit 1;
}

my $STRIPDIR = $SUBSTDIR;

my $URIROOT = '';

$SUBSTDIR =~ s#\/+#\\\/\+#g;
$URIROOT = '(file\:)?\/\/' . $SUBSTDIR . "\\\/\+html\\\/\+";
$STRIPDIR =~ s#\/+#\\\/\+#g;
$STRIPDIR .= '\/+html\/+';

my $BSDESTDIR = $DESTDIR;
$BSDESTDIR =~ s#\\#/#g;

my $BSSDESTDIR = $DESTDIR;
$BSSDESTDIR =~ s#/#\\#g;

print "Replacing $SUBSTDIR with $DESTDIR\n";

my @dirs = @ARGV;

if (!scalar @ARGV) {
    @dirs = (cwd);
}

find(\&wanted, @dirs);

sub wanted {
	# $File::Find::dir has directory name, $_ filename
	# and $File::find::name has complete filename
	#
	my $filename  = $_;

	# ignore symlinks and others
	#
	return if (! -f || -B);

        # ignore subversion base files
        return if ($File::Find::dir =~ /\/.svn/ || $File::Find::dir =~ /\/CVS/);
        
        # Special case, executable names containing periods
        return if (/^httpd\.(worker|prefork|event)/);

        # General case, binary names
        return if (/\.(a|so|xs|sl|lib|dll|exe)$/);

        # Binary names with no period suffix, excluding script names
        if (!/\./) {
            return if ( !/^dbmmanage$/ && !/^envvars$/ && !/^envvars-std$/ 
                     && !/^apxs$/ && !/^httpdctl$/ && !/^apachectl$/
		     && !/^c_rehash$/ && !/-config$/);
        }
			
	my $permissions = (stat($filename))[2];
	my $timestamp   = (stat($filename))[9];
	my $tmpname     = $filename . ".tmp~";
	my $foundp      = 0;
	my $foundu      = 0;

        my $RELPATH = $File::Find::dir . '/';
        $RELPATH =~ s#(${STRIPDIR})##i;
        if ($^O =~ /Win32/) {
            $RELPATH =~ s#\\+#\/#;
        }        
        $RELPATH =~ s#^\/+##g;
        $RELPATH =~ s#[^\/]+#..#g;        

	if ($^O =~ /Win32/) {
	    # defines in the .h / Config.pm files must be double backslashed.
	    if ($filename =~ /\.h$/i || $filename =~ /Config.pm$/i) {
		$DESTDIR = $BSSDESTDIR;
	    } else {
		$DESTDIR = $BSDESTDIR;
	    }
	}

	if (!open(FHIN, "<".$filename)) {
	    warn "$0 could not open $filename: $!$/";
	    return;
	}
	if (!open(FHOUT, ">".$tmpname)) {
	    warn "$0 could not open $tmpname: $!$/";
	    return;
	}

	binmode FHIN;
	binmode FHOUT;

        while (<FHIN>) {
  	    if ($_ =~ s#(${URIROOT})#$RELPATH#g) {
		$foundu = 1;
	    }
  	    if ($_ =~ s#(${SUBSTDIR})#$DESTDIR#g) {
		$foundp = 1;
	    }
	    print FHOUT $_;  # this prints to tmpname'ed file
	}

	close(FHOUT);
	close(FHIN);

	if ($foundp || $foundu) {
            my $bakname = $filename . ".bak~";
	    rename($filename, $bakname);
	    rename($tmpname, $filename);
	    unlink($bakname);

	    my @filenames = ($filename);
	    utime $timestamp, $timestamp, @filenames;
	    chmod($permissions, $filename);

            print $File::Find::dir . '/' . $filename . "\n";
	}
	else {
	    unlink($tmpname);
        }
}