#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;

my $debhome = "/mnt/debhome";
my $svn = "/mnt/svn";

# default paths for debhome and svn
# these are constant
my $debhomepathoriginal = "/mnt/ad64/debhome";
my $svnpathoriginal = "/mnt/ad64/svn";

######################################################
# sub to restore links /mnt/svn /mnt/debhome
# to the default original values if they have changed
# parameters: chroot directory
######################################################
sub restorechrootlinks{
	my ($chroot_dir) = $_[0];

	# /mnt/svn and /mnt/debhome may be
	# directories.
	rmdir $chroot_dir . $svn if -d $chroot_dir . $svn;
	rmdir $chroot_dir . $debhome if -d $chroot_dir . $debhome;

	# debhomepath is of form /mnt/ad64/debhome
	# svnpath is of form /mnt/ad64/svn
	# (name, path) = fileparse(fullpath)
	my $debhomemount = (fileparse($debhomepathoriginal))[1];
	my $svnmount = (fileparse($svnpathoriginal))[1];
	
	# make dirs incase they do not exist
	mkdir "$chroot_dir" . "$debhomemount" unless -d "$chroot_dir" . "$debhomemount";
	mkdir "$chroot_dir" . "$svnmount" unless -d "$chroot_dir" . "$svnmount";

	# make the link for /mnt/debhome -> /chroot_dir/mnt/ad64/debhome in the chroot environment
	unlink "$chroot_dir" . "$debhome";
	my $rc = system("chroot $chroot_dir ln -v -s $debhomepathoriginal $debhome");
	die "Error making $debhome -> $debhomepathoriginal link in chroot: $!" unless $rc == 0;

	# make the link for /mnt/svn -> /chroot_dir/$svnpath in the chroot environment
	unlink "$chroot_dir" . "$svn";
	$rc = system("chroot $chroot_dir ln -v -s $svnpathoriginal $svn");
	die "Could not make link $svn -> $svnpathoriginal in chroot: $!" unless $rc == 0;

	# set ownership
	system("chown robert:robert -h $chroot_dir" . "$svn");
	system("chown robert:robert -h $chroot_dir" . "$debhome");
	system("chown robert:robert $chroot_dir" . "/mnt");

}	

#######################################################
# sub to unbind sys tmp dev dev/pts proc for chroot
# environment
# usage: unbindall chroot_dir, restorelinks
# returns: none
# exceptions: dies if chroot dir does not exist
#######################################################
sub unbindall {
	# parameters
	my $chroot_dir = $_[0];
	die "$chroot_dir does not exist, exiting\n" unless -d $chroot_dir;

	# bind for all in list
	my @bindlist = ("$debhome", "$svn", "/sys", "/tmp", "/dev/pts", "/dev", "/proc");
	my $rc;
	foreach my $dir (@bindlist) {
		$rc = system("findmnt $chroot_dir" . "$dir 2>&1 >/dev/null");
		if ($rc == 0) {
			# dir mounted, unmount it
			print "$chroot_dir" . "$dir unmounted\n";
			$rc = system("umount $chroot_dir" . "$dir");
			die "Could not umount $chroot_dir" . "$dir: $!\n" unless $rc == 0;
		} else {
			# dir not mounted
			print "$chroot_dir" . "$dir not mounted\n";
		}
	}

	# check that /chroot/mnt/debhome and /chroot/mnt/svn do not contain
	# any files. If they do, abort
	# open directory
	foreach my $dir ($chroot_dir . $debhome, $chroot_dir . $svn) {

		# the directory may not exist
		unless( -d $dir) {
			opendir (my $dh, $dir) || die "Could not open directory $dir: $!\n";
			my @nofiles = readdir $dh;
			closedir $dh;
			# remove count for . and ..
			my $nofiles = scalar(@nofiles) - 2;
			die "$dir still contains $nofiles files\n" if $nofiles > 0;
		}
	}
	

	# restore the links in the chroot environment
	restorechrootlinks($chroot_dir);
}
die "Usage: unbindall chroot directory\n" unless $ARGV[0];
unbindall $ARGV[0];
