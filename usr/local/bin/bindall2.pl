#!/usr/bin/perl
#######################################################
# sub to bind sys tmp dev dev/pts proc for chroot
# environment
# access to debhome and svn in the chroot environment
# is done through the binding of /mnt/debhome to /chroot/mnt/debhome
# and for svn /mnt/svn to /chroot/mnt/svn
# the directories are made in by bindall in the
# chroot environment
# usage: bindall chroot_dir
# returns: none
# exceptions: dies if chroot dir does not exist
#######################################################
use strict;
use warnings;

my $debhome = "/mnt/debhome";
my $svn = "/mnt/svn";

sub bindall {
	# parameters
	my $chroot_dir = $_[0];
	chdir $chroot_dir or die "$chroot_dir does not exist, exiting\n";

	# bind all in list
	# bind for all in list
	my @bindlist = ("/proc", "/dev", "/dev/pts", "/tmp", "/sys", "$svn", "$debhome");
	my $rc;

	# if links exist delete them
	unlink $chroot_dir . $svn if -l $chroot_dir . $svn;
	unlink $chroot_dir . $debhome if -l $chroot_dir . $debhome;
	
	# make directories for debhome and svn
	if (! -d $chroot_dir . $svn) {
		$rc = mkdir "$chroot_dir" . "$svn";
		die "Could not make directory $chroot_dir" . "$svn" unless $rc;
	}

	# for debhome
	if (! -d $chroot_dir . $debhome) {
		$rc = mkdir "$chroot_dir" . "$debhome";
		die "Could not make directory $chroot_dir" . "$debhome" unless $rc;
	}

	foreach my $dir (@bindlist) {
		# check if it is already mounted
		$rc = system("findmnt $chroot_dir" . "$dir 2>&1 >/dev/null");
		unless ($rc == 0) {
			# not mounted, mount dir
			$rc = system("mount --bind $dir $chroot_dir" . "$dir");
			die "Could not bind $chroot_dir" . "$dir: $!\n" unless $rc == 0;
			print "$chroot_dir" . "$dir mounted\n";
		} else {
			# already mounted
			print "$chroot_dir" . "$dir is already mounted\n";
		}
	}
}
die "Usage: bindall chroot directory\n" unless $ARGV[0];
bindall $ARGV[0];
