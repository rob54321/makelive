#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Std;
use File::Basename;
use File::Path qw (make_path);

###################################################
# Global constants
###################################################
# global constant links for debhome and subversion
# sources for macrium and recovery
# the source directory is the root of MACRIUM, MCTREC, RECOVERY or SOURCES
my $svn = "/mnt/svn";
my $debhome = "/mnt/debhome";
my $macriumsource = "/mnt/ad64/debhome/livesystem";

# path to RECOVERY files
my $recoverysource = "/mnt/ad64/debhome/livesystem";

# path to MCTREC file
my $mctrecsource = "/mnt/ad64/debhome/livesystem";

# default for SOURCES path
my $sourcessource = "/mnt/ad64/debhome/livesystem";
# sizes of MCTREC and RECOVERY partitions
my $recoverysize = 1;
my $mctrecsize = 8;

# parent directory of sources
my $MACRIUM = "MACRIUM";
my $MCTREC = "MCTREC";
my $RECOVERY = "RECOVERY";
my $SOURCES = "SOURCES";

# default paths for debhome and svn
# these are constant
my $debhomepathoriginal = "/mnt/ad64/debhome";
my $svnpathoriginal = "/mnt/ad64/svn";
###################################################

# get command line arguments
our($opt_m, $opt_i, $opt_c, $opt_e, $opt_u, $opt_p, $opt_s, $opt_D, $opt_S, $opt_h, $opt_d, $opt_M, $opt_R, $opt_T, $opt_V);

#######################################################
# this script makes a live system on a partition
# called linux. This script will also partition
# and format a disk for the live system.
# partition 1: 8G fat32 for LINUXLIVE and MACRIUM
# partition 2: 8G fat32 for MCTREC
# partition 3: 1G fat32 for RECOVERY
# partition 4: 100% ntfs for ele contains sources directory for RECOVERY
#
#
#######################################################


###################################################
# sub to mount devices
# simple script to mount a device
# if mounted , umount all locations.
# then mount with the options
# finish and klaar
# returns:
# 0 success and was not mounted
# +n success mounted n times including at correct location
# -n success mounted n times and not at correct location
# on failure script will die.
###################################################
sub mountdevice {
	# parameters
	my $label = shift @_;
	my $mtpt = shift @_;
	my $options = shift @_;

	# if no options given, use defaults
	# which is read only
	$options = "ro" unless ($options);

	# check if device is mounted and if mounted multiple times
	my @target = `findmnt --source LABEL=$label -o TARGET`;
	chomp(@target);

	# return codes
	my $rc;

	# flag to indicate it was mounted
	my $wasmounted = "false";

	# indicates no of mounts
	my $noofmounts = 0;
			
	#@target = ("TARGET", mountpoint)
	# it may be mounted at multiple locations
	# one of the locations may or may not be correct
	if (@target) {
		# device is mounted at lease once

		#get rid of header TARGET
		shift @target;

		# umount all mounts
		foreach my $item (@target) {
			# umount label
			$rc = system("umount -v $item");
			die "Could not umount $label from $item: $!\n" unless $rc == 0;
			$noofmounts++;
			
			# if label was mounted at correct mountpoint
			# set flag to enable return status
			$wasmounted = "true" if "$item" eq "$mtpt";
		}
		# all mounts now un mounted for the device
	}

	# mount the device
	# make mount directory if not found
	make_path($mtpt) unless -d $mtpt;
	
	$rc = system("mount -L $label -o $options $mtpt");
	die "Could not mount $label at $mtpt -o $options: $!\n" unless $rc == 0;
	print "mounted $label at $mtpt options: $options\n";

	if ("$wasmounted" eq "true") {
		return $noofmounts;
	} else {
		return $noofmounts * -1;
	}
}

###################################################################
# sub to find the source files for installfiles sub
# the source must be a full path with no links it it such as
#
#   /mnt/ad64/debhome/livesystem/MACRIUM | MCTREC | RECOVERY | SOURCES
# or
#   /home/robert/MACRIUM | MCTREC | RECOVERY | SOURCES
# or 
#   /mnt/chaos/MACRIUM
# parent directory of each source could be MACRIUM, MCTREC, RECOVERY or SOURCES
# the source could be a block device or a directory
#
# if the source exists then return
# if source never found then die
# to look for the source
# 1 check if an element of path is a block device
# try and mount it if it is

# parameters passed: source path (which cannot contain links)
###################################################################
sub findsource {
	# get source
	my $source = shift @_;

	# if the source exists return
	if (-d $source) {
		print "found $source";
		return;
	}

	# source does not exist.
	# check if it is a block device
	# and try and mount it.
	
	# get all path elements of the source
	my @pathelements = split /\//, $source;
	chomp(@pathelements);
	
	# the first element is "" since path is /...
	# remove it 
	shift @pathelements;
print "path elements @pathelements\n";
	# check if the path is on a block device
	# that is attached, if not die
	# get the attached block devices
	my @blkdev = `lsblk -l -o LABEL`;
	chomp(@blkdev);
	
	# check if a block device matches
	# a path element
	my $device;
	# used to find index of device element in blkdev
	my $count = 0;
	LOOP: foreach my $dir (@pathelements) {
		foreach my $bdev (@blkdev) {
#print "bdev $bdev    path elements $dir\n";
			if ("$dir" eq "$bdev") {
				$device = $bdev;
				last LOOP;
			}
		}
		$count++;
	}
#print "device = $device count = $count\n";
	# if device was found
	# try and mount it else source not found -- die
	if ($device) {
		# try and mount it
		# determine the mount point
		# path might be /a/b/c/d/MACRIUM
		# then device might be c
		# then mount point is /a/b
		# all elements before the device in pathelements
		my $mountpoint = "/";
		# if path is /mnt/ad64/debhome/livesyste/MACRIUM
		# then mount point is /mnt/ad64
		for(my $i=0; $i<=$count; $i++) {
			# append elements to make path
			$mountpoint = $mountpoint . $pathelements[$i] . "/";
		}
#print "device = $device mountpoint = $mountpoint\n";
		
		mountdevice($device, $mountpoint, "ro");
		# check if the source exists
		if ( -d $source ) {
			print "found $source: mounted $device at $mountpoint\n";
			return;
		} else {
			# source not found
			# umount it 
			system("umount -v $mountpoint");
			die "Could not find $source with device = $device mounted at $mountpoint\n";
		}
	} else {
		# no device found
		die "Could not find $source and path is not on a block device\n";
	}
}

#######################################################
# sub to restore /mnt/debhome and /mnt/svn links
# in main system
# parameters: none
#######################################################
sub restoremainlinks {
	# restore links in main system
	# to the original values
	my $link;

	# for svn
	if (-l $svn) {
		$link = readlink $svn;
		if ("$link" ne "$svnpathoriginal") {
			unlink $svn;
			symlink ($svnpathoriginal, $svn);
			# set ownership
			system("chown robert:robert -h $svn");
		}
	} else {
		# link does not exist
		# make it
		symlink ($svnpathoriginal, $svn);
		# set ownership
		system("chown robert:robert -h $svn");
	}
	# for debhome
	if (-l $debhome) {
		$link = readlink $debhome;
		if ("$link" ne "$debhomepathoriginal") {
			unlink $debhome;
			symlink ($debhomepathoriginal, $debhome);
			# set ownership
			system("chown robert:robert -h $debhome");
		}
	} else {
		# link does not exist
		# make it
		symlink ($debhomepathoriginal, $debhome);
		# set ownership
		system("chown robert:robert -h $debhome");
	}

}
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
######################################################
# sub to delete all partitions and make a
# partition 1: 1G fat32 for MACRIUM REFLECT LABEL = MACRIUM uuid = AED6-434E
# partition 2: 8G (default - or selectable) fat32 for linux live LABEL = LINUXLIVE uuid = 3333-3333
# partition 3: 2G fat32 LABEL =  RECOVERY uuid = 4444-4444
# partition 3: rest of disk ntfs LABEL = ele
# all data on the disk is deleted.
# the partitions are also formatted.
# parameters passed: partition size in GB
# sub aborts on any error
# requires: disk for MACRIUM to be attached, not mounted
######################################################
sub partitiondisk {
	# get size of first partition
	my $linuxlivesize = $_[0];

	# show devices attached
	print "######################################################\n";
	my $rc = system("lsblk -o PATH,TYPE,MODEL,LABEL,MOUNTPOINT");
	die "aborting: error from lsblk\n" unless $rc == 0;
	print "######################################################\n";

	# get the device
	print "\n\nenter device to be formatted: form /dev/sdX\n";

	my $device = <STDIN>;
	chomp($device);

	# show the device to check
	print "\n######################################################\n";
	$rc = system("parted -s $device print");
	die "aborting: error from parted\n" unless $rc == 0;
	print "######################################################\n";

	print "\n\nAll data on $device will be deleted: is this correct (yes|no)?\n";
	my $answer = <STDIN>;
	chomp($answer);

	if ($answer =~ /^yes$/i) {
		print "partitioning $device\n";

		# partition 1: LINUXLIVE partition size is passed as a parameter to this sub
		# partition 2: MCTREC size is 8GB media tool creation recovery
		# partition 3: RECOVERY size is 1Gb
		# partition 4: ele partition is 100% and contains sources for RECOVERY
		my $p1start = 0;
		my $p1end = $linuxlivesize;
		my $p2start = $p1end;
		my $p2end = $p2start + $mctrecsize; 
		my $p3start = $p2end;
		my $p3end = $p3start + $recoverysize;
		my $p4start = $p3end;
		my $p4end = "100%";

		# convert p start and end to XXGB string
		$p1start .= "GB";
		$p1end   .= "GB";
		$p2start .= "GB";
		$p2end   .= "GB";
		$p3start .= "GB";
		$p3end   .= "GB";
		$p4start .= "GB";
		
		# delete all partitions and make new ones
		$rc = system("parted -s --align optimal $device mktable msdos mkpart primary fat32 $p1start $p1end mkpart primary fat32 $p2start $p2end mkpart primary fat32 $p3start $p3end mkpart primary ntfs  $p4start $p4end set 1 boot on");
		die "aborting: error partitioning $device\n" unless $rc == 0;

		# format the first partition
		# the sleep is needed to let the disk settle
		# after partitioning. With no sleep formatting fails
		# if partition size is bigger than 12GB
		sleep 2;

		# format partition 1
		print "formatting partition " . $device . "1\n";
		$rc = system( "mkfs.vfat -v -n LINUXLIVE -i AED6434E " . $device . "1");
		die "aborting: error formatting " . $device . "1\n" unless $rc == 0;

		# format second partition
		print "formatting partition " . $device . "2\n";
		$rc = system("mkfs.vfat -v -n MCTREC -i 22222222 " . $device . "2");
		die "aborting: error formatting " . $device . "2\n" unless $rc == 0;

		# format third partition
		print "formatting partition " . $device . "3\n";
		$rc = system("mkfs.vfat -v -n RECOVERY -i 33333333 " . $device . "3");
		die "aborting: error formatting " . $device . "3\n" unless $rc == 0;

		# format forth partition
		print "formatting partition " . $device . "4\n";
		$rc = system("mkfs.ntfs -v -Q -L ele  " . $device . "4");
		die "aborting: error formatting " . $device . "4\n" unless $rc == 0;

	} else {
		print "$device was not partitioned\n";
	}
}


##############################################################################
# this sub operates on the list @ARGV
# all the switches in the ARGV list are checked to see if they have arguments
# if they do not have arguments, the default arguments are inserted into ARGV
# so that getopts will not fail.
# no parameters are passed and none are returned.
# requires: none
##############################################################################
sub defaultparameter {

	# hash supplying default arguments to switches
	# -b is for mounting bit locker drives
	# -v is for mounting vera containers
	# -u is for unmounting any drive
	# the default argument, if not given on the command line is all drives
	my %defparam = ( -c => "none",
			 -D => 8,
			 -M => "$macriumsource",
			 -R => "$recoverysource",
			 -S => "$sourcessource",
			 -T => "$mctrecsource");

	# for each switch in the defparam hash find it's index and insert default arguments if necessary
	foreach my $switch (keys(%defparam)) {
		# find index of position of -*
		my $i = 0;
		foreach my $param (@ARGV) {
			# check for a -b and that it is not the last parameter
			if ($param eq $switch) {
				if ($i < $#ARGV) {
					# -* has been found at $ARGV[$i] and it is not the last parameter
					# if the next parameter is a switch -something
					# then -* has no arguments
					# check if next parameter is a switch
					if ($ARGV[$i+1] =~ /^-/) {
						# -* is followed by a switch and is not the last switch
						# insert the 2 default filenames as a string at index $i+1
						my $index = $i + 1;
						splice @ARGV, $index, 0, $defparam{$switch};
					}
				} else {
					# the switch is the last in the list so def arguments must be appended
					my $index = $i + 1;
					splice @ARGV, $index, 0, $defparam{$switch}; 
				}
			}
			# increment index counter
			$i++;
		}
	}
} 
####################################################
# sub to make filesystem.squashfs.
# dochroot must have been done
# filesystem.squashfs is written to chroot1/dochroot
# not All directories under /mnt must be empty
# no devices should be mounted
# parameters: chroot directory
# requires: none
####################################################
sub makefs {
	my $chroot_dir = $_[0];
	
	# check that dochroot has been executed previously
	die "dochroot has not been executed\n" unless -d "$chroot_dir/dochroot";

	# if the file exists, delete it
	# or mksquashfs will fail.
	unlink "$chroot_dir/dochroot/filesystem.squashfs";
	
	# make the file system the boot directory must be included, config-xxxx file is needed by initramfs during install
	my $rc = system("mksquashfs " . $chroot_dir . " $chroot_dir/dochroot/filesystem.squashfs -e oldboot -e dochroot -e upgrade -e packages -e isoimage");
	die "mksquashfs returned and error\n" unless $rc == 0;
}
######################################################
# sub to edit grub default and set the theme in the filesystem.squashfs
# parameters: chroot dir
# requires: no devices to be mounted
######################################################
sub editgrub {
	my $chroot_dir = $_[0];
	
	# set /etc/default/grub, GRUB-CMDLINE_LINUX_DEFAULT=""
	system("sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"\"/' $chroot_dir/etc/default/grub");
	# set colours
	system("sed -i -e 's/menu_color_normal=.*/menu_color_normal=white\\/blue\"/' -e 's/menu_color_highlight=.*/menu_color_highlight=yellow\\/black\"/' $chroot_dir/etc/grub.d/05_debian_theme");

}

#######################################################
# sub to write version and code name to disk
# the version and code name are retrieved
# from a string in /mnt/cdrom/.disk/info file
# parameters chroot_dir
# requirements, iso image must be mounted
#######################################################
sub saveversioncodename {
	my $chroot_dir = $_[0];
	
	# the file /mnt/cdrom/.disk/info contains the codename and version of linux
	# read this file and store the codename in chroot_dir/isoimage/codename.txt
	# and store the version in chroot_dir/isoimage/version.txt
	#open /mnt/cdrom/.disk/info for reading
	open DISK, "<", "/mnt/cdrom/.disk/info" or die "could not open /mnt/cdrom/.disk/info: $!\n";
	my $string = <DISK>;
	chomp($string);
	close DISK;
	
	# file is of form:
	# Ubuntu-MATE 24.04 "Noble Numbat" - Daily amd64 (20231101)
	# get version , which could be 23.04 or 2300
	my ($version, $codename);
	
	my @matches = $string =~ /\s+(\d+\.\d+)\s+/;

	# if nothing found search for version of form 2300
	# with no decimal point
	if (@matches == 0) {
		# match of form 2300 not found
		@matches = $string =~ /\s+(\d+)\s+/;
		if (@matches == 0) {
			# could not find the version of form 2300 or 23.04
			# enter it manually
			print "Could not find the version of linux, enter it below\n";
			$version = <STDIN>;
			chomp($version);
		} else {
			# version found 
			$version = $matches[0];
		}
	} else {
		# match found of form 23.04
		$version = $matches[0];
	}
	
	# get the codename
	@matches = $string =~ /\s+"(\w+)\s+/;
	if (@matches == 0) {
		# the code name could not be found
		# enter it manually
		print "the code name could not be found, enter it below\n";
		$codename = <STDIN>;
		chomp($codename);
	} else {
		# code name found
		$codename = $matches[0];
	}

	# convert codename to lower case
	$codename = lc $codename;
	
	print "codename = $codename: version = $version\n";

	# write codename and version to files in chroot_dir/isoimage/codename.txt
	# and chroot_dir/isoimage/version.txt
	open VERSION, ">", "$chroot_dir/isoimage/version.txt" or die "could not save $version to $chroot_dir/isoimage/version.txt: $!\n";
	print VERSION "$version";
	close VERSION;
	open CODENAME, ">", "$chroot_dir/isoimage/codename.txt" or die "could not save $codename to $chroot_dir/isoimage/codename.txt: $!\n";
	print CODENAME "$codename";
	close CODENAME;

}
#######################################################
# sub to get codename from the cdrom
# the name is in /mnt/cdrom/dists   impish
# which is a directory.
# the cdrom must be mounted
# and the codename is returned if found
# else undefined is returned.
# parameters: chroot_dir
# returns codename
# requires: nothing
#######################################################
sub getcodename {
	my $chroot_dir = $_[0];
	
	# read file chroot_dir/isoimage/codename.txt
	open CODENAME, "<", "$chroot_dir/isoimage/codename.txt" or die "could not open $chroot_dir/isoimage/codename.txt: $!\n";
	my $codename = <CODENAME>;
	chomp($codename);
	
        return $codename;
}

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
			# $dir must be accessible
			# so debhome and svn must be accessible or bind will fail.
			$rc = system("mount --bind $dir $chroot_dir" . "$dir");
			die "Could not bind $chroot_dir" . "$dir: $!\n" unless $rc == 0;
			print "$chroot_dir" . "$dir mounted\n";
		} else {
			# already mounted
			print "$chroot_dir" . "$dir is already mounted\n";
		}
	}
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
		if ( -d $dir) {
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
	
#################################################
# this sub sets up sources.list and debhome.list
# in chroot_dir/etc/apt and chroot_dir/etc/apt/sources.list.d
# The call setaptsources (codename, chroot_dir)
# requires: svn
#################################################
sub setaptsources {
	my ($codename, $chroot_dir) = @_;
	my $rc;
	# create sources.list
	open (SOURCES, ">", "$chroot_dir/etc/apt/sources.list");
	print SOURCES "deb http://archive.ubuntu.com/ubuntu $codename main restricted multiverse universe
deb http://archive.ubuntu.com/ubuntu $codename-security main restricted multiverse universe
deb http://archive.ubuntu.com/ubuntu $codename-updates  main restricted multiverse universe
deb http://archive.ubuntu.com/ubuntu $codename-proposed  main restricted multiverse universe\n";
	close SOURCES;

	# debhome.sources and debhomepubkey.asc are installed from liveinstall package now.
	# extract debhome.sources from  subversion to /etc/apt/sources.list.d/debhome.sources
	do 
	{
		$rc = system("svn export --force file://$svn/root/my-linux/sources/amd64/debhome.sources  " . $chroot_dir . "/etc/apt/sources.list.d/");
		die "Could not export debhome.sources from svn\n" unless $rc == 0;
	} unless ( -f $chroot_dir . "/etc/apt/sources.list.d/debhome.sources");

	# get the public key for debhome
	# make the /etc/apt/keyrings directory if it does not exist
	mkdir "/etc/apt/keyrings" unless -d "/etc/apt/keyrings";
	
	do 
	{
		$rc = system("svn export --force file://$svn/root/my-linux/sources/gpg/debhomepubkey.asc  " . $chroot_dir . "/etc/apt/keyrings/");
		die "Could not export debhomepubkey.asc from svn\n" unless $rc == 0;
	} unless (-f $chroot_dir . "/etc/apt/keyrings/debhomepubkey.asc");	

}
############################################################
# umount the cdrom.
# sometimes it is still busy.
# needs some time ater use to umount
############################################################
sub umountcdrom {
	# un mount /mnt/cdrom
	my $rc = system("findmnt /mnt/cdrom");
	system("umount -d -v -f /mnt/cdrom") if $rc == 0;
}

############################################################
# sub to mount cdrom
# un mounts anything on /mnt/cdrom
# then mounts cdrom at /mnt/cdrom
# fstab edited so debhomedev can be mounted
# debhomedev directory made
# links /mnt/debhome and /mnt/svn are made
# parameters to pass: iso-name
############################################################
sub mountcdrom {
	my $isoimage = $_[0];
	my $rc;

	# if /mnt/cdrom exists, unmount iso image if it is mounted
	# mount ubuntu-mate iso image
	if (-d "/mnt/cdrom") {
		print "checking if cdrom is mounted\n";
		$rc = system("findmnt /mnt/cdrom");

		# umount /mnt/cdrom
		system("umount -v /mnt/cdrom") if $rc == 0;
	} else {
		# /mnt/cdrom does not exist, create it
		mkdir "/mnt/cdrom";
	}

	$rc = system("mount -o ro,loop " . $isoimage . " /mnt/cdrom");
	die "Could not mount $isoimage\n" unless $rc == 0;
}

#######################################################
# remakelink removes the link and makes it again
# to point to the correct directory
# parameters: path, link
#######################################################
sub remakelink {
	my ($repopath, $link) = @_;
		unlink $link;
		my $rc = symlink $repopath, $link;
		# if link could not be made, die
		die "Could not link $link -> $repopath\n" unless $rc;

		# change ownership
		$rc = system("chown -h robert:robert $link");
		die "Could not change ownership of $link: $!\n" unless $rc == 0;
}

#######################################################
# pathtype
# determins the path type of svn or debhome
# parameters : repopath, ref to type which will be set
# returns: actual_device or where_link_points_to or directory_of_svn/debhome or file_name_if_file or 0
# corresponding to type: "device" or "link" or "directory" or "file" or "unknown"
# reference to type
#######################################################
sub pathtype {
	my $repopath = shift @_;
	my $refdescription = shift @_;
	my $reponame = basename($repopath);
print "pathtype: repopath = $repopath refdescription = $refdescription reponame = $reponame\n";
	
	# if path = /mnt/device/svn or /mnt/device/a/b/c/d/e/debhome
	# the match delimeter m? ? only matches once. cannot be used.
	if ($repopath =~ m/\/mnt\/.*\/$reponame/) {
		# path is of form /mnt/something/svn
		# is 'something a block device'
		my $device = (split(/\//, $repopath))[2];
print "pathtype: device = $device\n";
		my $rc = system("blkid -L $device");
		if ($rc == 0) {
			# device is a block device
			# set the refdescription
			$$refdescription = "device";
			return $device;
		}
	} elsif (-l $repopath) {
		#repopath is a link
		$$refdescription = "link";
		# where does the link point to
		my $destination = readlink $repopath;
		return $destination;
	} elsif (-d $repopath) {
		# repopath is a directory
		$$refdescription = "directory";
		return $repopath;
	} elsif (-f $repopath) {
		# repopath is a regular file
		$$refdescription = "file";
		return $repopath;
	} else {
		# unknown type
		$$refdescription =  "unknown";
		return 0;
	}
}

#######################################################	
# findrepo:
# if path to repo does not exist
# 	check if path is of form /mnt/device/svn|debhome
# 	if not die
# 	if it is a block device try and mount it
# 	else die
# 	now check if repo exists or die
# 	remake the link
# else 
# 	path found
#	remake the link
#end
# parameters: repopath, $link  (/mnt/svn or /mnt/debhome)
#######################################################
sub findrepo {
	my ($repopath, $link) = @_;

	my ($rc, $device);

	# repo name is svn or debhome
	# repo path is /mnt/ad64/debhome or /mnt/ad64/svn
	my $reponame = basename($repopath);
	
	# check what type the path to the repo is
	# link or dir or contains a device
	# as in /mnt/device/svn or /mnt/device/debhome
	# descripion is device or link or directory or file or unknown
	# type is actual_device or where_link_points_to or directory_name or file_name or 0
	my $description;
#print "findrepo: calling pathtype: params repopath = $repopath ref = " . \$description . "\n";
	my $repopathtype = pathtype($repopath, \$description);
#print "findrepo: repopath = $repopath description = $description repopathtype = $repopathtype\n";

	# check if the repo is found at the repo path
	if (! -d $repopath) {
		# the repo was not found
		# the path may contain a device
		# which needs to be mounted
		# for a device
		if ($description eq "device") {
			$rc = mountdevice($repopathtype, "/mnt/$repopathtype", "ro") if $description eq "device";
			# if $rc >= 1 device was already mounted at correct location
			# but repo was not found, die
			die "Device $repopathtype is mounted and $reponame not found\n" if $rc >= 1;

			# device is now mounted

			# check that svn | debhome found
			# un mount if not
			if (! -d $repopath) {
				# svn | debhome not found, umount device and die
				system("umount -v /mnt/$repopathtype");
				die "Could not find $reponame on device $repopathtype at $repopath\n";
			}

			# device is mounted found repository
		} elsif ($description eq "directory") {
			# repo path is a directory
			# and repo not found
			# die. type is the directory
			die "Could not find repository $reponame at directory $repopath\n";
		} elsif ($description eq "link") {
			# repository not found at link -> type
			#$repopathtype  is where the link points to 
			die "Could not find repository $reponame at link $repopathtype\n";

		} elsif ($description eq "file") {
			# the repo path is a file not a directory
			# therefore it does not exist
			die "Repository path for $reponame is a file not a directory: $repopath\n";
		} elsif ($description eq "unknown") {
			# unknown type
			die "Repository path for $reponame is unknown: $repopath\n";
		}
	} else {
		# the repository path exists
		# if it is on a device, mount the device
		# ro to protect it from being deleted by
		# createchroot function
		# get the path type
print "findrepo: $reponame exists at $repopath\n";
print "findrepo: calling pathtype repopath = $repopath\n";
		$repopathtype = pathtype($repopath, \$description);
print "findrepo: pathtype: repopathtype = $repopathtype description = $description\n";

		# remount device ro
		mountdevice($repopathtype, "/mnt/$repopathtype", "ro") if $description eq "device";

		# repopathtype may also be a directory
		# which should be protected, not sure how
		#==============================================================================
		# figure out how to make a directory read only
		#==============================================================================
	}
	# the path does exist check the link
	remakelink $repopath, $link;

	print "found $reponame at $repopath\n";
}

##################################################################
# sub to set up new chroot environment.
# the environment is copied from the cdrom
# makes the links /mnt/debhome and /mnt/svn in the chroot environment
# parameters passed: chroot_directory, isoimage
# requires: mountcdrom to be mounted
####################################################################
sub createchroot {
	# creating new chroot environment
	my ($chroot_dir, $isoimage, $debhomepath, $svnpath) = @_;
	my $rc;
		
	# delete the old chroot environment if it exists
	# make sure debhome and svn are not mounted
	# as the flash drive they are on will get deleted.
	if (-d $chroot_dir) {
		# chroot dir exists unbindall
		unbindall $chroot_dir;
		# check if $chroot_dir/boot is mounted in chroot environment
		# need to protect the live drive
		# incase the binds are still active
		$rc = system("findmnt $chroot_dir/boot");
		if ($rc == 0) {
			# un mount drive
			$rc = system("umount -v $chroot_dir/boot");
			die "Could not umount $chroot_dir/boot\n" unless $rc == 0;
		}

		# remove directory
		$rc = system("rm -rf $chroot_dir");
		die "cannot remove $chroot_dir\n" unless $rc == 0;
		print "removed $chroot_dir\n";
	}

	#####################################################################################
	# copy and edit files to chroot
	#####################################################################################
	# mount the cdrom
	mountcdrom $isoimage;
	
	# unsquash filesystem.squashfs to the chroot directory
	# the chroot_dir directory must not exist
	$rc = system("unsquashfs -d " . $chroot_dir . " /mnt/cdrom/casper/filesystem.squashfs");
	die "Error unsquashing /mnt/cdrom/casper/filesystem.squashfs\n"unless $rc == 0;
	print "unsquashed filesystem.squashfs\n";
		
	# copy resolv.conf and interfaces so network will work
	system("cp /etc/resolv.conf /etc/hosts " . $chroot_dir . "/etc/");
	system("cp /etc/network/interfaces " . $chroot_dir . "/etc/network/");

	system("cp -dR /etc/apt/trusted.gpg.d " . $chroot_dir . "/etc/apt/");
	system("cp -a /etc/apt/trusted.gpg " . $chroot_dir . "/etc/apt/") if -f "/etc/apt/trusted.gpg";

	# copy vmlinuz and initrd from cdrom to
	# $chroot_dir/oldboot incase there is no
	# upgrade for the kernel. If there was 
	# an upgrade by liveinstall the new
	# vmlinuz and initrd will be copied over
	# the original ones.
	mkdir "$chroot_dir/oldboot" or die "could not make $chroot_dir/oldboot: $!\n";
	system("cp -vf /mnt/cdrom/casper/vmlinuz /mnt/cdrom/casper/initrd $chroot_dir/oldboot");
	
	# copy pool and install files for ubuntu mate
	# to a temp directory $chroot_dir/isoimage
	chdir "/mnt/cdrom";
	mkdir "$chroot_dir/isoimage" unless -d "$chroot_dir/isoimage";
	
	$rc = system("cp -dR .disk dists install pool preseed " . $chroot_dir . "/isoimage/");
	die "could not copy dists install pool preseed to $chroot_dir/isoimage: $!\n" unless $rc == 0;

	# save the version and codename of linux
	saveversioncodename ($chroot_dir);
	
	# umount cdrom
	chdir "/root";
	umountcdrom;
}

###############################################
# sub to change root  and run liveinstall.sh
# makes a dir dochroot to indicate dochroot was run
# also deletes filesystem.squashfs in dochroot
# since it will now change.
# debhome and svn are accessed from the chroot environment
# by binding /mnt/debhome and /mnt/svn to /mnt/debhome and /mnt/svn
# in the chroot environment
# installfs will use filesystem.squashfs if it exists
# also requires svn if packages and or upgrade are done.
# parameters: chroot_directory, upgrade, packages_list
# requires: /mnt/debhome and /mnt/svn to be binded to debhome and svn
###############################################
sub dochroot {
	my ($chroot_dir, $upgrade, $packages) = @_;

	# get codename
	open CDN, "<", "$chroot_dir/isoimage/codename.txt" or die "could not open $chroot_dir/isoimage/codename.txt: $!\n";
	my $codename = <CDN>;
	chomp($codename);
	close CDN;
	print "code name is: $codename\n";


	# generate chroot_dir/etc/apt/sources.list
	# and chroot_dir/etc/sources.list.d/debhome.list
	setaptsources ($codename, $chroot_dir);

	# copy xwindows themes and icons to /usr/share
	# if themes.tar.xz and icons.tar.xz are found
	my $rc;
	if (-f "$debhome/xconfig/themes.tar.xz") {
		$rc = system("tar --xz -xf $debhome/xconfig/themes.tar.xz -C $chroot_dir/usr/share");
		die "Could not extract themes from $debhome/themes.tar.xz" unless $rc == 0;
	}

	# if themes.tar.xz and icons.tar.xz are found
	if (-f "$debhome/xconfig/icons.tar.xz") {
		$rc = system("tar --xz -xf $debhome/xconfig/icons.tar.xz -C $chroot_dir/usr/share");
		die "Could not extract themes from $debhome/xconfig/icons.tar.xz" unless $rc == 0;
	}
	
	#############################################################################################
	# enter the chroot environment
	#############################################################################################

	# install apps in the chroot environment
	bindall $chroot_dir;

	# chroot/mnt/debhome and /chroot/mnt/svn are bound to /mnt/debhome and /mnt/svn
	# mount debhome in the chroot environment
	#$rc = system("chroot $chroot_dir mount -r -L $debhomedev /mnt/$debhomedev");
	#die "Could not mount $debhomedev in chroot environment: $!\n" unless $rc == 0;
	
	# parameters must be quoted for Bash
	# liveinstall.sh "-u "upgrade/noupgrade" -p "package list"
	# make parameters list for liveinstall.sh
	# parameters is set to " " so that if only packages is given
	# there won't be a warning.
	my $parameters = " ";
	$parameters = "-u " if $upgrade;
	$parameters = $parameters . "-p " . $packages if $packages;
	
	# execute liveinstall.sh in the chroot environment
	print "parameters: $parameters\n" if $parameters;

	# liveinstall is a package in the dehome distribution
	# so debhome must be setup for liveinstall to be
	# installed
	# do an update and install liveinstall
	$rc = system("chroot $chroot_dir apt update");
	die "Could not apt update in chroot environment $!\n" unless $rc == 0;

	# live install depends on subversion and git.
	# this is how subversion and git are installed
	# in the chroot environment
	$rc = system("chroot $chroot_dir apt install -y liveinstall");
	die "Could not install liveinstall in chroot environment $!\n" unless $rc == 0;

	# now execute liveinstall and check the return
	my $lirc = system("chroot $chroot_dir liveinstall.sh $parameters");
	
	#*********************** TBD ************************
	#####################################################
	
	# umount debhome in the chroot environment
	#$rc = system("chroot $chroot_dir umount /mnt/$debhomedev");
	#die "Could not umount $debhomedev in chroot environment: $!\n" unless $rc == 0;
	
	# for exiting the chroot environment
	# unbind debhome and svn
	# reset chroot links
	unbindall $chroot_dir;

	# check if liveinstall exited with error in chroot environment
	die "liveinstall.sh exited with error" unless $lirc == 0;
	# liveinstall.sh will create directory dochroot
	# to indicate chroot was done.
	# filesystem.squashfs must be deleted in /dochroot
	# because the filesystem will have changed.
}

#######################################################
# this sub determines the version
# which will be used for grub
# the full iso name is in $chroot_dir/isoimage/version.txt
# parameter passed: $chroot_dir
# returns version
# requirements: none
######################################################
sub getversion {
	my $chroot_dir = $_[0];
	
	################################
	# determine the version for grub
	# get the iso name from $chroot_dir/isoimage/isoimage.txt
	################################

	# read the file 
	open ISO, "<", "$chroot_dir/isoimage/version.txt" or die "could not open $chroot_dir/isoimage/isoimage.txt: $!\n";
	my $version = <ISO>;
	chomp($version);
	close ISO;
	
	return $version;
}

#################################################
# copies files for MACRIUM -M, RECOVERY and SOURCES -R or -S, MCTREC -T
# the root directories of the soures must be MACRIUM or RECOVERY or SOURCES
# needs /mnt/debhome by default
# the files are copied to the respective partition
# parameter: full path to source eg /mnt/debhome/livesystem/MACRIUM, partition label, target root directory on partition
# the source directory is not created
#################################################
sub installfiles {
	my $source = shift @_;
	my $label = shift @_;
	my $rootdir = shift @_;
	
	# return codes
	my $rc;

	# check that the source does exist and copy or else die
	# find source by mounting block device
	# retrieved from the path
	findsource($source);

	# mount the destination parition
	$rc = mountdevice($label, "/mnt/$label", "ro");

	# source found, copy it
	$rc = system("cp -dRv -T $source /mnt/$label" . "$rootdir");
	die "Could not copy $source to /mnt/$label" . "$rootdir: $!\n" unless $rc == 0;

	#un mount the destination drive
	$rc = system("umount /mnt/$label");
	die "Could not umount $label: $!\n" unless $rc == 0;
}
	
#################################################
# this sub sets up grub and installs it.
# this is only necessary for partition 1
# the call: installgrub(chroot_directory, partition_path)
# requires: svn and LINUXLIVE
#################################################
sub installgrub {
	
	##########################################################################################################
	# export the grub.cfg for mbr and uefi and edit grub only for partition 1
	##########################################################################################################
	my ($chroot_dir, $partition_path) = @_;
	my $rc;

	# export grub
	$rc = system("svn export --force --depth files file://$svn/root/my-linux/livescripts/grub/vfat/mbr/ " . $chroot_dir . "/boot/grub/");
	die "Could not export mbr grub\n" unless $rc == 0;
	$rc = system("svn export --force --depth files file://$svn/root/my-linux/livescripts/grub/vfat/efi/ " . $chroot_dir . "/boot/EFI/grub/");
	die "Could not export efi grub\n" unless $rc == 0;
	
	# now edit grub.cfg with the new version no.
	# edit mbr grub and set version
	# get version
	my $version = getversion($chroot_dir);
    
	chdir $chroot_dir . "/boot/grub";
	system("sed -i -e 's/ubuntu-version/$version/' grub.cfg");
	chdir $chroot_dir . "/boot/EFI/grub";
	system("sed -i -e 's/ubuntu-version/$version/' grub.cfg");

	# this doesn't seem necessary from MACRIUM version 7.3
	# rename macrium file to stop only macrium_pe booting
	#system("mv " . $chroot_dir . "/boot/EFI/Microsoft/Boot/bootmgfw.efi "
	#             . $chroot_dir . "/boot/EFI/Microsoft/Boot/bootmgfw.efi.old")
	#             if -e $chroot_dir . "/boot/EFI/Microsoft/Boot/bootmgfw.efi";

	# install grub
	# get device from partition path
	my $device = $partition_path;
	# partition_path is a partion device: eg /dev/sda1

	# remove last char to get the device path eg: /dev/sda
	chop $device;
	print "$device\n";
	system("grub-install --no-floppy --boot-directory=" . $chroot_dir . "/boot --target=i386-pc " . $device);
	
	system(" grub-install --no-floppy --boot-directory=" . $chroot_dir . "/boot/EFI --efi-directory="  . $chroot_dir . "/boot --removable --target=x86_64-efi " . $device);
}

####################################################
# sub to build filesystem.squashfs, copy dists, install
# pool preseed to /boot on drive.
# install and edit grub
# create the writable file for persistence
# and copy to casper
# uses filesystem.squashfs if it exists in dochroot
# else it builds if from scratch.
# this speeds up the process of install if filesystem.squashfs has not changed
# requires LINUXLIVE and svn to be mounted
####################################################
sub installfs {
	# parameters
	my ($label, $casper, $chroot_dir) = @_;
	
	# check if chroot environment exists
	die "$chroot_dir does not exist\n" unless -d $chroot_dir;

	# check that dochroot has been executed previously
	die "dochroot has not been executed\n" unless -d "$chroot_dir/dochroot";
	
	# check LINUXLIVE is attached
	my $rc = system("blkid -L " . $label . " > /dev/null");
	die "$label is not attached\n" unless $rc == 0;
	
	# get partition_path of partition LINUXLIVE/UBUNTU ex: /dev/sda1
	my $partition_path = `blkid -L $label`;
	chomp $partition_path;
	print $label . " is: $partition_path\n";
	
	# check if the partition, LINUXLIVE  is mounted at any location
	# un mount it if it is mounted
	my $devandmtpt = `grep "$partition_path" /etc/mtab | cut -d " " -f 1-2`;
	chomp($devandmtpt);
	my ($dev, $mtpt) = split /\s+/, $devandmtpt;

	# if label LINUXLIVE|UBUNTU is mounted, un mount it
	if (defined $mtpt) {
		print "$label mounted at: $mtpt\n";
		$rc = system("umount $mtpt");
		die "$label cannot be unmounted\n" unless $rc == 0;
	}

	#############################################################################################
	# copy and edit files to chroot/boot
	#############################################################################################
	# if there is a filesystem.squashfs in dochroot
	# use it. If it does not exist it must be created
	# sub dochroot deletes it since filesystem.squashfs
	# would change if dochroot is invoked.
	makefs($chroot_dir) unless -f "$chroot_dir/dochroot/filesystem.squashfs";

	# empty /chroot1/boot
	# this must be done after makefs, the config-xxxx-generic file
	# must be in the filesystem.squashfs for initramfs to work
	# during linux installation
	chdir $chroot_dir . "/boot";
	system ("rm -rf *");

	# mount the partition LINUXLIVE/UBUNTU under 
	# chroot/boot, it was unmounted before chroot
	$rc = mountdevice($label, "$chroot_dir/boot", "ro");

	# make casper dir if it does not exist
	if ( -d $casper) {
		# clean directory
		system("rm -rf $casper");
	}
	# create directory
	mkdir $casper;
	
	# createchroot now makes $chroot_dir/oldboot and
	# copies vmlinuz and initrd from the cdrom to oldboot.
	# if an upgrade of the kernel was done liveinstall
	# will have copied the newer vmlinuz and initrd to oldboot
	# should have done this originally.
	# vmlinuz and initrd must be copied to casper
	$rc = system("cp -fv $chroot_dir/oldboot/initrd $casper");
	die "Could not copy initrd\n" unless $rc == 0;
	$rc = system("cp -fv $chroot_dir/oldboot/vmlinuz $casper");
	die "Could not copy vmlinuz\n" unless $rc == 0;
	# do not delete oldboot, incase chroot1 is used again

	# delete ubuntu install files in chroot/boot
	chdir $chroot_dir . "/boot";
	system("rm -rf .disk dists install pool preseed grub");
	
	# copy pool and install files for ubuntu mate
	chdir "$chroot_dir/isoimage";
	system("cp -dR .disk dists install pool preseed " . $chroot_dir . "/boot/");
	
	# make a boot directory on LINUXLIVE
	# so that there is no error message from grub
	# at boot time that no /boot/ found.
	mkdir $chroot_dir . "/boot/boot";
		
	# setup and install grub if this is the first partition
	installgrub($chroot_dir, $partition_path);
	
	# set grub colours
	editgrub($chroot_dir);
	
	# make the persistence file
	chdir $casper;
	system("dd if=/dev/zero of=writable bs=1M count=3000");
	system("mkfs.ext4 -v -j -F writable");

	# so chroot1/boot can be unmounted
	chdir "/root";
	
	
	$rc = system("cp -vf $chroot_dir/dochroot/filesystem.squashfs " . $casper);
	die "Could not move /tmp/filesystem.squashfs to $casper\n" unless $rc == 0;
	
	# umount chroot boot
	system("umount " . $chroot_dir . "/boot");
	$rc = system("findmnt " . $chroot_dir . "/boot");
	print "count not umount " . $chroot_dir . "/boot\n" if $rc == 0;
}

####################################################
# sub to initialise the setup of the LINUXLIVE partition.
# if -c given create new chroot from scratch or use existing one
# parameters passed:
# createchroot, ubuntuiso-name, upgrade, debhome path, svn full path, packages list)
####################################################
sub initialise {
	my ($doinstall, $makefs, $isoimage, $upgrade, $dochroot, $debhomepath, $svnpath, $packages)  = @_;

	# set up chroot dir
	my $chroot_dir = "/chroot";
	
	# die if no /choot and it is not being created
	if (! -d $chroot_dir) {
		die "chroot environment does not exist\n" unless $isoimage;
	}
	
	# some short cuts depending on the parition number
	my $casper = $chroot_dir . "/boot/casper";
	my $label = "LINUXLIVE";
		
	# if p or u given then set chrootuse
	# if chroot does not exist then set chroot
	print "packages: $packages\n" if $packages;
	print "upgrade:\n" if $upgrade;
	
	# if creating new chroot
	# un mount debhomedev
	#==============================================
	# determine how to umount debhome and svn
	# before creating chroot
	# debhome and svn are bound to directories in chroot
	# they are not bound at startup.
	# dehomepath and svnpath are passed
	# to make sure they are unmounted
	# so the flash drive they are on does not
	# get deleted
	#==============================================

	createchroot($chroot_dir, $isoimage, $debhomepath, $svnpath) if $isoimage;
print "initialise: debhomepath = $debhomepath svnpath = $svnpath\n";

	# -i needs svn and linuxlive
	# -u -p -e need svn and debhome
	# -c needs cdrom
	# -m needs nothing

	if ($upgrade or $packages or $dochroot) {
		# svn and debhome needed
		findrepo($svnpath, $svn);
exit 0;
		# now find debhome
		findrepo($debhomepath, $debhome);

	} elsif ($doinstall) {
		# only -i was given, only svn and linuxlive are required
		# check that subversion is accessible
		# if subversion is not accessible try and mount it if it is a device
		# if subversion is not found die
		findrepo($svnpath, $svn);
	} # end of elsif ($doinstall)
	
	# if packages or upgrade defined dochroot must be done
	if ($packages or $upgrade or $dochroot) {
		# if chroot environment does not exist die
		die ("chroot environment does not exist\n") unless -d $chroot_dir;
		# dochroot must be done
		dochroot($chroot_dir, $upgrade, $packages);
		
	} elsif (($doinstall or $makefs) and (! -d "$chroot_dir/dochroot")) {
		# dochroot must be done if directory dochroot does not exist
		dochroot($chroot_dir, $upgrade, $packages);
	}
	
	
	# make filesystem.squashfs if not installing
	makefs($chroot_dir) if $makefs;

	###########################################################################
	# install MACRIUM files if -M given
	# install RECOVERY and SOURCES files if -R or -S given
	# install MCTREC files if -T given
	###########################################################################
	# setup the fullname source from the parent directory
	do {
		$opt_M = $opt_M . "/" . $MACRIUM;
		installfiles($opt_M, "LINUXLIVE", "/");
	} if $opt_M;

	do {
		# for recovery files
		# if opt_R is set append /RECOVERY
		# else set opt_R to default + /RECOVERY
		if ($opt_R) {
			# opt_R set append RECOVERY
			$opt_R = $opt_R . "/" . $RECOVERY;
		} else {
			# opt_R not set
			$opt_R = $recoverysource . "/" . $RECOVERY;
		}
		
		installfiles("$opt_R", "RECOVERY", "/");

		# for sources
		# if opt_S is set append /sources
		# else set opt_S to default + /sources
		if ($opt_S) {
			# opt_S is set, append /sources
			$opt_S = $opt_S . "/" . $SOURCES;
		} else {
			# opt_S is not set, set it to default + /sources		
			$opt_S = $sourcessource . "/" . $SOURCES;
		}
		# install the files
		installfiles("$opt_S", "ele", "/sources");
		
	} if $opt_R or $opt_S;

	# for MCTREC files
	do {
		$opt_T = $opt_T . "/" . $MCTREC;
		installfiles("$opt_T", "MCTREC", "/");
	} if $opt_T;
	
	# install in LINUXLIVE/UBUNTU
	installfs($label, $casper, $chroot_dir) if $doinstall;

}

sub usage {
	my ($debhomepath, $svnpath) = @_;
	print "-c iso name, create changeroot -- needs iso image\n";
	print "-u do a full-upgrade -- needs svn debhome\n";
	print "-e run dochroot -- needs svn debhome\n";
	print "-m make filesystem.squashfs, dochroot must be complete -- needs nothing\n";
	print "-p list of packages to install quotes -- needs svn debhome\n";
	print "-d full path for debhome, default is $debhomepath\n";
	print "-s full path to subversion, default is $svnpath\n";
	print "-D size of LINUXLIVE partition in GB default is 8GB fat32\n";
	print "-i install the image to LINUXLIVE\n";
	print "-M full parent directory of MACRIUM files, default is $macriumsource\n";
	print "-R full parent directory of RECOVERY files, default is $recoverysource\n";
	print "-S full parent directory of SOURCES files, default is $sourcessource\n";
	print "-T full parent directory of MCTREC files, default is $mctrecsource\n";
	print "-V check version and exit\n";
	exit 0;
}
##################
# Main entry point
##################

# command line parameters
# -c ubuntu-mate iso name or none (default)
# -p "package list of extra packages
# -u upgrade or not
# -s full path to subersion
# -d full path to dehome
# -D optional size in GB of partition
# One or both iso's can be given.
# package list in quotes, if given

# -i needs svn and LINUXLIVE
# -u -p -e need svn and debhome
# -c needs cdrom
# -m needs nothing

# get command line options

# default parameters for -d default is 8GB
defaultparameter();

getopts('mic:ep:hus:S:d:M:R:VD:T:');

# check version and exit 
if ($opt_V) {
	system("dpkg-query -W makelive");
	exit 0;
}

# setup debhome if it has changed from the default
my $debhomepath = $debhomepathoriginal;
$debhomepath = $opt_d if $opt_d;

my $svnpath = $svnpathoriginal;

# setup svn path if it has changed
# done here for usage sub
# svnpath overrides previous path
# if it has changed
$svnpath = $opt_s if $opt_s;
print "main: debhome = $debhomepath svn = $svnpath\n";

usage($debhomepath, $svnpath) if $opt_h;
# return code from functions
my $rc;

# check for packages and upgrade
# package list must be in quotes
my $packages = "\"" . $opt_p . "\"" if $opt_p;

# check if iso exists
if ($opt_c) {
	# check iso image exists
	die "iso image $opt_c does not exist\n" unless ((-f $opt_c) or ("$opt_c" eq "none"));
}

# if the -D option is given
# partition the disk imediately
# so the questions can be answered
# at the begining
# $opt_D is the size of GB of the partition

partitiondisk($opt_D) if $opt_D;

# initialise variables and invoke subs depending on cmdine parameters
initialise($opt_i, $opt_m, $opt_c, $opt_u, $opt_e, $debhomepath, $svnpath, $packages) if ($opt_c or $opt_u or $opt_e or $opt_p or $opt_i or $opt_m or $opt_M or $opt_R or $opt_S or $opt_T);

# restore main links
restoremainlinks;
