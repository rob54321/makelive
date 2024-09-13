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
# set up chroot dir
my $chroot_dir = "/chroot";

# the name of the squashfs file
# the name could be filesystem.squashfs or minimal.squashfs
# this value must be restored from a file $chroot_root/isoimage/makelive.restore.rc
my $squashfsfilename;
# list of all squashfs files on the cdrom
# this list is used to copy all of them to
# the live system. Required if version >= 24.04
# this list is restored between runs of makelive
my @squashfsfilelist;

# the version of ubuntu must be available across
# runs of makelive.pl
my $version;

# default paths for debhome and svn
# these are constant
my $debhomepathoriginal = "/mnt/ad64/debhome";
my $svnpathoriginal = "/mnt/ad64/svn";

# for the livesystem the chroot links /mnt/debhone
# and /mnt/svn point to these values below
my $debhomechrootoriginal = "/mnt/ad64/debhome";
my $svnchrootoriginal = "/mnt/ad64/svn";

# set the variables for the sources
# as they depend on debhomepath
my $macriumsource  = $debhome . "/livesystem";
my $recoverysource = $debhome . "/livesystem";
my $mctrecsource   = $debhome . "/livesystem";
my $sourcessource  = $debhome . "/livesystem";

# config file for saving svn and debhome links
my $config = "/root/.makelive.rc";

# debug flag, set to 1 for debug info
my $debug = 0;

# sizes of MCTREC and RECOVERY partitions
my $recoverysize = 1;
my $mctrecsize = 8;

# parent directory of sources
my $MACRIUM = "MACRIUM";
my $MCTREC = "MCTREC";
my $RECOVERY = "RECOVERY";
my $SOURCES = "SOURCES";

###################################################

# get command line arguments
our($opt_m, $opt_i, $opt_c, $opt_e, $opt_u, $opt_p, $opt_s, $opt_D, $opt_S, $opt_h, $opt_d, $opt_M, $opt_R, $opt_T, $opt_V, $opt_L, $opt_Z);

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

#######################################################
# sub to save current links for svn | debhome
# to a file so it can be loaded
# one or two links may change
# so write one or two links if both change
# params 1 svnpath
#        2 dehomepath
#######################################################
sub savelinks {
	# get the directories pointed to by links
	# first svn the debhome
	my $svnpath = shift @_;
	my $debhomepath = shift @_;

	# write them to a disk file
	# /root/makelive.rc
	# overwrite if it exists
	open (MKRC, ">", $config) or die "Could not open $config for writing: $!\n";
	print MKRC "$svnpath\n";
	print MKRC "$debhomepath\n";
	close MKRC;
}

###################################################
# sub to restore links from file
# for svn | debhome
# if the file does not exist
# then use the default settings
# no parameters passed
# on failure abort
###################################################
sub loadlinks {
	# see if file exists
	if (-f $config) {
		# open and read file
		open (FH, "<", $config) or die "Could not open $config for reading: $!\n";

		# set the global default variables for svn and debhome
		$svnpathoriginal = <FH>;
		chomp($svnpathoriginal);
		$debhomepathoriginal = <FH>;
		chomp($debhomepathoriginal);
		close FH;
	}
}
			
###################################################
# sub to mount devices
# simple script to mount a device
# if mounted , umount all locations.
# then mount with the options
# finish and klaar
# params: label mountpoint options true | false -- true for mount false for no mount
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

	# true for mount , false for no mount
	my $mount = shift @_;
	
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

		# the first element of @target is TARGET  for a title
		# remove it
		shift @target;
		
		# @target = (/mnt/ad64, /chroot/mnt/debhome, /chroot/mnt/svn)
		# reverse the order since /mnt/ad64 must be un mounted last
		my @rtarget = reverse @target;

		#also the 
		# umount all mounts
		foreach my $item (@rtarget) {
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

	if ($mount eq "true") {
		# mount the device
		# make mount directory if not found
		make_path($mtpt) unless -d $mtpt;

		# only mount if mount flag is true
		$rc = system("mount -L $label -o $options $mtpt");
		die "Could not mount $label at $mtpt -o $options: $!\n" unless $rc == 0;
		print "mounted $label at $mtpt options: $options\n" if $debug;
	}
	
	if ("$wasmounted" eq "true") {
		return $noofmounts;
	} else {
		return $noofmounts * -1;
	}
}

# sub to restore /mnt/debhome and /mnt/svn links
# in main system to default values
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
# sub to restore links /mnt/svn /mnt/debhome in chroot
# to the default original values for the chroot system
# these links are only used in the live system.
# In the chroot the directories /mnt/debhome /mnt/svn
# are bound to the same in the main system.
# in the live system /mnt/debhome /mnt/svn are links
# to /mnt/ad64/debhome and /mnt/ad64/svn by default.
# parameters: none
######################################################
sub restorechrootlinks {

	# if chroot_dir/chrootenvironment does not exist
	# just return
	return unless -d $chroot_dir . "/chrootenvironment";
	
	# bindall() maded /mnt/svn and /mnt/debhome directories for binding
	# in the chroot system. restore them to the links for the live system
	rmdir $chroot_dir . $svn if -d $chroot_dir . $svn;
	rmdir $chroot_dir . $debhome if -d $chroot_dir . $debhome;

	# debhomepath is of form /mnt/ad64/debhome
	# svnpath is of form /mnt/ad64/svn
	# (name, path) = fileparse(fullpath)
	my $debhomemount = (fileparse($debhomechrootoriginal))[1];
	my $svnmount = (fileparse($svnchrootoriginal))[1];
	
	# make dirs incase they do not exist
	print "restorechrootlinks in chroot: mkdir $chroot_dir" . "$debhomemount\n" if $debug;
	make_path("$chroot_dir" . "$debhomemount", {owner => "robert", user => "robert", group => "robert"}) unless -d "$chroot_dir" . "$debhomemount";

	print "restorechrootlinks in chroot: mkdir $chroot_dir" . "$svnmount\n" if $debug;
	make_path("$chroot_dir" . "$svnmount", {owner => "robert", user => "robert", group => "robert"}) unless -d "$chroot_dir" . "$svnmount";

	# make the link for /mnt/debhome -> /chroot_dir/mnt/ad64/debhome in the chroot environment
	unlink "$chroot_dir" . "$debhome";
	print "restorechrootlinks in chroot: $debhome -> $debhomechrootoriginal\n" if $debug;
	
	# check if chroot/bin/ln exists
	# die if it does not
	die "/bin/ln from coreutils does not exist\n" unless -f "/bin/ln";
	my $rc = system("chroot $chroot_dir ln -s $debhomechrootoriginal $debhome");
	die "restorechrootlinks in chroot: error making $debhome -> $debhomechrootoriginal link in chroot: $!" unless $rc == 0;

	# make the link for /mnt/svn -> /chroot_dir/$svnpath in the chroot environment
	unlink "$chroot_dir" . "$svn";
	print "restorechrootlinks in chroot: $svn -> $svnchrootoriginal\n" if $debug;
	$rc = system("chroot $chroot_dir ln -s $svnchrootoriginal $svn");
	die "restorechrootlinks in chroot: Could not make link $svn -> $svnchrootoriginal in chroot: $!" unless $rc == 0;

	# set ownership in chroot environment
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
# parameters: none
# requires: none
####################################################
sub makefs {
	
	# check that dochroot has been executed previously
	die "dochroot has not been executed\n" unless -d "$chroot_dir/dochroot";

	# if the file exists, delete it
	# or mksquashfs will fail.
	unlink "$chroot_dir/dochroot/$squashfsfilename";
	
	# make the file system the boot directory must be included, config-xxxx file is needed by initramfs during install
	my $rc = system("mksquashfs " . $chroot_dir . " $chroot_dir/dochroot/$squashfsfilename -e chrootenvironment -e oldboot -e dochroot -e upgrade -e packages -e isoimage");
	die "mksquashfs returned and error\n" unless $rc == 0;
}
######################################################
# sub to edit grub default and set the theme in the filesystem.squashfs
# parameters: none
# requires: no devices to be mounted
######################################################
sub editgrub {
	
	# set /etc/default/grub, GRUB-CMDLINE_LINUX_DEFAULT=""
	system("sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"\"/' $chroot_dir/etc/default/grub");
	# set colours
	system("sed -i -e 's/menu_color_normal=.*/menu_color_normal=white\\/blue\"/' -e 's/menu_color_highlight=.*/menu_color_highlight=yellow\\/black\"/' $chroot_dir/etc/grub.d/05_debian_theme");

}

#######################################################
# sub to restore squashfs file name  and list 
# $squashfsfilename and @squashfs if scalar(@squashfs) > 1
# parameters: none
# return: none
#######################################################
sub restoresquashfsvars {
	# open file or die
	open FR, "<", "$chroot_dir/isoimage/squashfsfilename.txt" or die "Could not open squashfsfilename.txt: $!\n";
	$squashfsfilename = <FR>;
	chomp($squashfsfilename);
	
	# restore @squashfs if it exists.
	# @squashfs may not exist if only filesystem.squashfs exists.
	# if multiple squashfs files exist, minimal.squashfs... then it exists
	if (-s "$chroot_dir/isoimage/squashfsfilelist.txt") {
		# reade file
		open FR, "<", "$chroot_dir/isoimage/squashfsfilelist.xt" or die "Could not open squashfsfilelist.txt: $!\n";
		@squashfsfilelist = <FR>;
		chomp(@squashfsfilelist);
	}
}

#######################################################
# sub to save the squashfs file name to 
# chroot_dir/isoimage/squashfs.txt
# parameters: none
# return: none
#######################################################
sub savesquashfsvars {
	# mkdir the directory if it does not exist
	make_path "$chroot_dir/isoimage" unless -d "$chroot_dir/isoimage";
	
	# open the file for writing
	# clobber the file if it exists
	open FW, ">", "$chroot_dir/isoimage/squashfsfilename.txt" or die "Could not open squashfsfilename.txt: $!\n";
	print FW $squashfsfilename;
	close FW;
	
	# save squashf file list
	open FW, ">", "$chroot_dir/isoimage/squashfsfilelist.txt" or die "Could not open squashfsfilelist.txt: $!\n";
	foreach my $file (@squashfsfilelist) {
		print FW "$file\n";
	}
	close FW;
}
	
#######################################################
# sub to write version and code name to disk
# the version and code name are retrieved
# from a string in /mnt/cdrom/.disk/info file
# parameters none
# requirements, iso image must be mounted
#######################################################
sub saveversioncodename {
	
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
	# version must also be saved to disk
	# so it is available across runs
	my $codename;
	
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
# sub to bind sys tmp dev dev/pts proc for chroot
# environment
# access to debhome and svn in the chroot environment
# is done through the binding of where /mnt/debhome points to
# to /chroot/mnt/debhome
# and for svn where /mnt/svn points to to /chroot/mnt/svn
# the directories are made by bindall in the
# chroot environment
# usage: bindall chroot_dir
# returns: none
# exceptions: dies if chroot dir does not exist
#######################################################
sub bindall {
	# parameters
	chdir $chroot_dir or die "$chroot_dir does not exist, exiting\n";

	# bind for all in list
	# /chroot/proc             binds to /proc
	# /chroot/dev              binds to /dev
	# /chroot/dev/pts          binds to /dev/pts
	# /chroot/tmp              binds to /tmp
	# /chroot/sys              binds to /sys
	# /chroot/mnt/svn          binds to where /mnt/svn points to
	# /chroot/mnt/debhome      binds to where /mnt/debhome points to
	my @bindlist = ("/proc", "/dev", "/dev/pts", "/tmp", "/sys", "$svn", "$debhome");
	my $rc;

	# flag to indicate dirs were bound and need to be 
	# unbound before being bound again
	my $runbindall = "false";
	
	# if links exist delete them
	# cannot bind a link to a directory for svn | debhome
	unlink $chroot_dir . $svn if -l $chroot_dir . $svn;
	unlink $chroot_dir . $debhome if -l $chroot_dir . $debhome;
	
	# make directories for debhome and svn
	if (! -d $chroot_dir . $svn) {
		$rc = make_path "$chroot_dir" . "$svn" unless -d $chroot_dir . $svn;
		die "Could not make directory $chroot_dir" . "$svn" unless $rc;
	}

	# for debhome
	if (! -d $chroot_dir . $debhome) {
		$rc = make_path "$chroot_dir" . "$debhome" unless -d $chroot_dir . $debhome;
		die "Could not make directory $chroot_dir" . "$debhome" unless $rc;
	}
	
	BIND: foreach my $dir (@bindlist) {
		# svn and debhome are bound read only. all others rw
		my $option;
		if ("$dir" eq "$svn" || "$dir" eq "$debhome") {
			$option = "-o ro";
		} else {
			$option = "-o rw";
		}
			
		# check if it is already mounted
		$rc = system("findmnt $chroot_dir" . "$dir 2>&1 >/dev/null");
		
		unless ($rc == 0) {
			# $dir must be accessible
			# so debhome and svn must be accessible or bind will fail.
			# bind svn and debhome ro
			# bind /chroot/mnt/svn to where /mnt/svn points to 
			# same for debhome
			if (-l $dir && ("$dir" eq "$svn" || "$dir" eq "$debhome")) {
				# bind svn and debhome to where link points to in main
				# get where link points to 
				my $sourcedir = readlink($dir);
				print "mount --bind $sourcedir $chroot_dir" . "$dir\n" if $debug;
				$rc = system("mount " . $option . " --bind $sourcedir $chroot_dir" . "$dir");
				die "Could not bind $chroot_dir" . "$dir to $sourcedir: $!\n" unless $rc == 0;
			} else {
				# bind all except svn and debhome
				print "mount --bind $dir $chroot_dir" . "$dir\n" if $debug;
				# make the directory incase it does not exist
				make_path $chroot_dir . $dir unless -d $chroot_dir . $dir;
				
				# bind the directories
				$rc = system("mount " . $option . " --bind $dir $chroot_dir" . "$dir");
				die "Could not bind $chroot_dir" . "$dir to $dir: $!\n" unless $rc == 0;
			}
		} else {
			# already mounted
			# exit the foreach loop and unbindall before starting again
			# set flag to run binall again
			print "invoking unbindall() from bindall()\n" if $debug;
			unbindall();

			$runbindall = "true";
			last BIND;
		}
	}
	# if dirs were unbound bind them again
	# check the debug flag
	if ($runbindall eq "true") {
		print "invoking bindall() again\n" if $debug;
		bindall();
	}
}

# sub to unbind sys tmp dev dev/pts proc for chroot
# environment
# usage: unbindall
# returns: none
# exceptions: dies if chroot dir does not exist
#######################################################
sub unbindall {
	# parameters
	die "$chroot_dir does not exist, exiting\n" unless -d $chroot_dir;

	# bind for all in list
	# reverse order compared to bindall()
	my @bindlist = ("$debhome", "$svn", "/sys", "/tmp", "/dev/pts", "/dev", "/proc");
	my $rc;
	foreach my $dir (@bindlist) {
		$rc = system("findmnt $chroot_dir" . "$dir 2>&1 >/dev/null");
		if ($rc == 0) {
			# dir mounted, unmount it
			print "$chroot_dir" . "$dir unmounted from $dir\n" if $debug;
			$rc = system("umount $chroot_dir" . "$dir");
			die "Could not umount $chroot_dir" . "$dir bound to $dir: $!\n" unless $rc == 0;
		} else {
			# dir not mounted
			print "$chroot_dir" . "$dir not mounted to $dir\n" if $debug;
		}
	}

	# check that /chroot/mnt/debhome and /chroot/mnt/svn do not contain
	# any files. If they do, abort
	# open directory
	foreach my $dir ($chroot_dir . $debhome, $chroot_dir . $svn) {

		# the directory must be empty
		# -d and -l are both true for a link
		# -l is false for a directory
		if ( ! -l $dir and -d $dir) {
			opendir (my $dh, $dir) || die "Could not open directory $dir: $!\n";
			my @nofiles = readdir $dh;
			closedir $dh;
			# remove count for . and ..
			my $nofiles = scalar(@nofiles) - 2;
			die "$dir still contains $nofiles files\n" if $nofiles > 0;
		}
	}
	
	# restore the links in the chroot environment
	restorechrootlinks();
}
	
#################################################
# this sub sets up sources.list and debhome.list
# in chroot_dir/etc/apt and chroot_dir/etc/apt/sources.list.d
# The call setaptsources (codename)
# requires: svn
#################################################
sub setaptsources {
	my ($codename) = @_;
	my $rc;
	# create sources.list
#	open (SOURCES, ">", "$chroot_dir/etc/apt/sources.list");
#	print SOURCES "deb http://archive.ubuntu.com/ubuntu $codename main restricted multiverse universe
#deb http://archive.ubuntu.com/ubuntu $codename-security main restricted multiverse universe
#deb http://archive.ubuntu.com/ubuntu $codename-updates  main restricted multiverse universe
#deb http://archive.ubuntu.com/ubuntu $codename-proposed  main restricted multiverse universe\n";
#	close SOURCES;

	# debhome.sources and debhomepubkey.asc are installed from liveinstall package now.
	# extract debhome.sources from  subversion to /etc/apt/sources.list.d/debhome.sources
	do 
	{
		$rc = system("svn export --force file://$svn/root/my-linux/sources/amd64/debhome.sources  " . $chroot_dir . "/etc/apt/sources.list.d/");
		die "Could not export debhome.sources from svn\n" unless $rc == 0;
	} unless ( -f $chroot_dir . "/etc/apt/sources.list.d/debhome.sources");

	# get the public key for debhome
	# make the /etc/apt/keyrings directory if it does not exist
	make_path "/etc/apt/keyrings" unless -d "/etc/apt/keyrings";
	
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
		print "checking if cdrom is mounted\n" if $debug;
		$rc = system("findmnt /mnt/cdrom");

		# umount /mnt/cdrom
		system("umount -v /mnt/cdrom") if $rc == 0;
	} else {
		# /mnt/cdrom does not exist, create it
		make_path "/mnt/cdrom";
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

###########################################
# sub to determine if path is on a device
# or not. Also determine the mountpoint
# eg if path is /a/b/ad64/d/e/svn
# then device is ad64
# and mount point is /a/b/ad64
# parameters: path, ref to array for returning
# device, mountpoint.
# if device is not found the array is empty
###########################################
sub getdevicemtpt {
	# parameters passed
	my $path = shift @_;
	my $refdevmtpt = shift @_;
	
	# find device among elements
	my @pathelements = split (/\//, $path);

	# remove first empty element
	# first element is empty.
	# it is the element to the left of
	#  /a/b/ad64/c/d....
	shift @pathelements;

	my $device;
	my $mtpt = "/";

	# check each element to see if it is adevice
	LOOP: foreach my $ele (@pathelements) {
		my $rc = system("blkid -L $ele > /dev/null 2>&1");
		if ($rc == 0) {
			# device found exit loop
			$device = $ele;
			last LOOP;
		} else {
			# append element to mount point
			# until device found
			$mtpt = $mtpt . $ele . "/";
		}
	}


	if (defined $device) {
		# make the mountpoint
		$mtpt = $mtpt . $device;

		# setup the reference to the list to contain
		# (device, mtpt)
		$refdevmtpt->[0] = $device;
		$refdevmtpt->[1] = $mtpt;
		print "device = $device mount point = $mtpt\n" if $debug;
	} else {
		# leave array devicemtpt empty
		print "no device found\n" if $debug;
	}
}

#######################################################
# pathtype
# determins the path type of svn or debhome
# parameters : repopath, ref to list which will contain (description, device, mount point) if they exist
# desription: device, link, directory, file or unknown.
# device: will be device and next element will be mount point if found
# if description is link next element contains directory pointed to
# if description is a directory next element is the directory
# if description is a file next element is the full path to file
# if description is unknown next element is 0
# return nothing
#######################################################
sub pathtype {
	my $repopath = shift @_;
	my $refdesdevmtpt = shift @_;
	
	# get name of svn or debhome
	my $reponame = basename($repopath);
	print "pathtype: repopath = $repopath reponame = $reponame\n" if $debug;
	
	# if path is on a device get device and mount point
	# the path could be /a/b/c/ad64/d/e/f/svn | debhome
	# device would be ad64 and mountpoint would be /a/b/c/ad64.
	# sub getdevicemtpt returns device and mount point.
	# if it is not a device return list is empty.
	# getdevicemtpt(path, ref to array)
	# array->[0] = device
	# array->[1] = mountpoint
	# array undefined if path does not contain a device
	my @devmtpt;
	getdevicemtpt($repopath, \@devmtpt);
	
	# if path is on a device
	# then $devmtpt[0] is the defined device
	# $devmtpt[1] is the mount point for that device path
	if ($devmtpt[0]) {
		# path is on a device		
		print "pathtype: device = $devmtpt[0] mount point is $devmtpt[1]\n" if $debug;
		# set the description
		$refdesdevmtpt->[0] = "device";
		# set the device
		$refdesdevmtpt->[1] = $devmtpt[0];
		# set the mount point
		$refdesdevmtpt->[2] = $devmtpt[1];
		return;

	} elsif (-l $repopath) {
		#repopath is a link
		$refdesdevmtpt->[0] = "link";
		# where does the link point to
		my $destination = readlink $repopath;
		# set arrary[1] to where link points to 
		$refdesdevmtpt->[1] = $destination;
		return;
		
	} elsif (-d $repopath) {
		# repopath is a directory
		$refdesdevmtpt->[0] = "directory";
		# set array[1] to actual directory
		$refdesdevmtpt->[1] = $repopath;
		return;

	} elsif (-f $repopath) {
		# repopath is a regular file
		$refdesdevmtpt->[0] = "file";
		# set array[1] to the actual file
		$refdesdevmtpt->[1] = $repopath;
		return;

	} else {
		# unknown type
		$refdesdevmtpt->[0] =  "unknown";
		# set array[1] to 0;
		$refdesdevmtpt->[1] = 0;
		return;
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
	my @desdevmtpt;
	print "findrepo: calling pathtype: params repopath = $repopath ref = " . \@desdevmtpt . "\n" if $debug;
	pathtype($repopath, \@desdevmtpt);
	do {
		if ($desdevmtpt[0] eq "device") {
			print "findrepo: repopath = $repopath description = $desdevmtpt[0] device = $desdevmtpt[1] mount point = $desdevmtpt[2]\n";
		} else {
			print "findrepo: repopath = $repopath description = $desdevmtpt[0] 2nd element = $desdevmtpt[1]\n";
		}
	} if $debug;
	# $repodir is the directory the found link points to
	# on a device. The link may exist on the device pointing
	# to the repository or source.
	# check if the repo is found at the repo path

	if (! -d $repopath) {
		# the repo was not found
		# the path may contain a device
		# which needs to be mounted
		# for a device
		# on the device there may be a link to the repository or source
		if ($desdevmtpt[0] eq "device") {
			$rc = mountdevice($desdevmtpt[1], $desdevmtpt[2], "ro", "true");

			# device is mounted, the repo or source could be
			# a directory or a link on the device
			# check that the repo | source is found.
			if (! -d $repopath && ! -l $repopath) {
				# repo | source not found umount device and die
				system("umount -v $desdevmtpt[2]");
				die "Could not find $reponame on device $desdevmtpt[1] at $repopath\n";
			} elsif (-l $repopath) {
				# repopath is a link
				# determine where the link points to
				# that value should have reponame as a suffix
				# $repodir is the directory where
				# $repopath points to
				my $repodir = readlink $repopath;
				print "$repopath is a link on device $desdevmtpt[1] mounted at $desdevmtpt[2] and points to $repodir\n" if $debug;
				
				# does repodir have reponame as a basename?
				if ($reponame ne basename($repodir)) {
					# repodir is not a directory to the repo | source
					die "The link $repopath -> $repodir which is not a repository for $reponame\n";
				}
			} elsif (-d $repopath) {
				# repopath is a directory on the device
				print "$reponame found on device $desdevmtpt[1] mounted at $desdevmtpt[2]\n" if $debug;
			}


		} elsif ($desdevmtpt[0] eq "device not attached") {
			# svn | debhome is on a device of form /mnt/device/svn | /mnt/device/debhome
			# but the device is not attached so svn | debhome not available
			print "$desdevmtpt[1] is not attached for $repopath\n";
			print "please attach $desdevmtpt[1]\n";
			die "Device $desdevmtpt[1] not attached, could not find $repopath\n";

			# device is mounted found repository

		} elsif ($desdevmtpt[0] eq "directory") {
			# repo path is a directory
			# and repo not found
			# die. type is the directory
			print "$repopath is a directory but $reponame was not found there\n" if $debug;
			die "Could not find repository $reponame at directory $repopath\n";

		} elsif ($desdevmtpt[0] eq "link") {
			# $repoath is a link
			#$desdevmtpt[1]  is where the link points to
			# check if directory where it points to has reponame as suffix
			if ($reponame eq basename($desdevmtpt[1])) {
				# base name of repopath is correct
				# now check if it exists
				if (! -d $desdevmtpt[1]) {
					# the directory of the repo | source does not exist
					die "$reponame does not exist at $desdevmtpt[1]\n";
				}	

			} else {	
				# suffix of directory is not reponame
				# repo | source not found
				print "$repopath is a link to $desdevmtpt[1]\n" if $debug;
				die "Could not find repository $reponame at link $repopath -> $desdevmtpt[1]\n";
			}

		} elsif ($desdevmtpt[0] eq "file") {
			# the repo path is a file not a directory
			# therefore it does not exist
			die "Repository path for $reponame is a file not a directory: $repopath\n";

		} elsif ($desdevmtpt[0] eq "unknown") {
			# unknown type
			die "Repository path for $reponame is unknown: $repopath\n";
		}

	} else {
		# the repository path exists
		# if it is a directory on a device, remount the device
		# ro to protect it from being deleted by
		# createchroot function
		# get the path type
		print "findrepo: $reponame exists at $repopath\n" if $debug;
		print "findrepo: calling pathtype repopath = $repopath\n" if $debug;
		pathtype($repopath, \@desdevmtpt);
		print "findrepo: pathtype: repopathtype = $desdevmtpt[1] description = $desdevmtpt[0]\n" if $debug;

		# remount device ro
		mountdevice($desdevmtpt[1], $desdevmtpt[2], "ro", "true") if $desdevmtpt[0] eq "device";

		# repopathtype may also be a directory
		# which should be protected, not sure how
		#==============================================================================
		# figure out how to make a directory read only
		#==============================================================================
	}

	# the path does exist check the link, remake the link if required
	# $link may or may not exist
	remakelink $repopath, $link if $link;

	print "found $reponame at $repopath\n";
}

################################################################
# sub to open /mnt/cdrom/casper and read all *.squashfs files
# ask the user which one to use.
# Also saves the squashfs name in squashfsfilename.txt
# and saves the list of squashfs files in squashfsfilelist.txt
# parameter passed: the directory to read
# return the squashfs file
################################################################
sub getsquashfs {
	my $directory = shift @_;
	
	# open directory
	opendir(my $dh, $directory) || die "Can't open directory $directory: $!\n";
	
	#read all files into a list
	my @filelist = readdir $dh;
	close $dh;
	

	# remove terminator
	chomp(@filelist);
	
	# remove . and .. from filelist
	shift @filelist;
	shift @filelist;
	
	# push all .squashfs files into a new list @squashfsfilelist
	foreach my $file (@filelist) {
		print "file: $file\n" if $debug;
		
		push @squashfsfilelist, $file if $file =~ /\.squashfs$/;
	}

	#######################################################################
	# @squashfsfilelist contains a list of all the .squashfs files in casper
	# for version >= 24.04 all must be copied to $chroot/isoimage
	#
	# if @squashfs only contains one file, then do not prompt
	# use this filename which will be filesystem.squashfs.
	# this is the case prior to 24.04
	#######################################################################
	if (scalar(@squashfsfilelist) > 1) {
		# file counter for menu
		my $i;
		
		# display list of .squashfs files for selection
		# in menu
		for ($i=0; $i < scalar(@squashfsfilelist); $i++) {
			print "$i: $squashfsfilelist[$i]\n";
		}
		
		# select a file from the menu
		print "Enter your selection 0 to "  . $#squashfsfilelist . "\n";
		my $answer = <STDIN>;
		# check that the number 1 <=  answer <= max = scalar(@squashfs)
		while ($answer < 0 || $answer > $#squashfsfilelist) {
			# try again
			print "Try again\n";
			$answer = <STDIN>;
		}
		
		# set the name of the squashfs file name
		$squashfsfilename = $squashfsfilelist[$answer];
	} elsif (scalar(@squashfsfilelist) == 1) {
		# there is only one file name
		# use this filename and do not prompt
		$squashfsfilename = $squashfsfilelist[0];
	}
	print "squashfs file selected: $squashfsfilename\n";

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
	my ($isoimage, $debhomepath, $svnpath) = @_;
	my $rc;
		
	# if svn | debhome mounted on a device
	# unmount it
	my @desdevmtpt;
	print "createchroot: calling pathtype $svnpath " . \@desdevmtpt . "\n" if $debug;
	pathtype($svnpath, \@desdevmtpt);
	print "createchroot after pathtype: device = $desdevmtpt[1] svnpath = $svnpath debhomepath = $debhomepath description = $desdevmtpt[0] svn = $svn debhome = $debhome\n" if $debug;

	mountdevice($desdevmtpt[1], $desdevmtpt[2], "ro", "false") if $desdevmtpt[0] eq "device";

	# for debhome
	pathtype($debhomepath, \@desdevmtpt);
	print "createchroot after pathtype: device = $desdevmtpt[1] svnpath = $svnpath debhomepath = $debhomepath description = $desdevmtpt[0] svn = $svn debhome = $debhome\n" if $debug;

	mountdevice($desdevmtpt[1], $desdevmtpt[2], "ro", "false") if $desdevmtpt[0] eq "device";

	# delete the old chroot environment if it exists
	# make sure debhome and svn are not mounted
	# as the flash drive they are on will get deleted.
	if (-d $chroot_dir) {

		# chroot dir exists unbindall
		unbindall ();
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
		print "createchroot: about to remove $chroot_dir\n" if $debug;
		$rc = system("rm -rf $chroot_dir");
		die "cannot remove $chroot_dir\n" unless $rc == 0;
		print "removed $chroot_dir\n" if $debug;
	}

	#####################################################################################
	# copy and edit files to chroot
	#####################################################################################
	# mount the cdrom
	mountcdrom $isoimage;
	
	# unsquash filesystem.squashfs to the chroot directory
	# the chroot_dir directory must not exist
	# the new versions of ubuntu-mate and ubuntu do not use
	# filesystem.squashfs. they use minimal.squashfs, minimal.standard.squashfs etc.
	# open casper directory to see all squashfs files and
	# prompt the user whicn one to use.

	# make the squashfs file name a global name
	# so it can be created and installed with the same name
	# set the squashfs file name $squashfsfilename
	getsquashfs("/mnt/cdrom/casper");
	
	$rc = system("unsquashfs -d " . $chroot_dir . " /mnt/cdrom/casper/" . $squashfsfilename);
	die "Error unsquashing /mnt/cdrom/casper/$squashfsfilename\n"unless $rc == 0;
	print "unsquashed $squashfsfilename\n" if $debug;
		
	# copy resolv.conf and interfaces so network will work
	system("cp /etc/resolv.conf /etc/hosts " . $chroot_dir . "/etc/");
	
	# make directory if it does not exist
	make_path $chroot_dir . "/etc/network" unless -d $chroot_dir . "/etc/network";
	system("cp /etc/network/interfaces " . $chroot_dir . "/etc/network/");

	system("cp -dR /etc/apt/trusted.gpg.d " . $chroot_dir . "/etc/apt/");
	system("cp -a /etc/apt/trusted.gpg " . $chroot_dir . "/etc/apt/") if -f "/etc/apt/trusted.gpg";

	# copy vmlinuz and initrd from cdrom to
	# $chroot_dir/oldboot incase there is no
	# upgrade for the kernel. If there was 
	# an upgrade by liveinstall the new
	# vmlinuz and initrd will be copied over
	# the original ones.
	make_path "$chroot_dir/oldboot" or die "could not make $chroot_dir/oldboot: $!\n";
	system("cp -vf /mnt/cdrom/casper/vmlinuz /mnt/cdrom/casper/initrd $chroot_dir/oldboot");
	
	#########################################################################################
	# if multiple squashfs files exist in /mnt/cdrom/casper, copy them all except
	# filesystem.squashfs for version < 24.04 and minimal.squashfs for version >= 24.04
	
	# copy pool and install files for ubuntu mate
	# to a temp directory $chroot_dir/isoimage
	chdir "/mnt/cdrom";
	make_path "$chroot_dir/isoimage" unless -d "$chroot_dir/isoimage";
	
	$rc = system("cp -dR .disk dists install pool preseed " . $chroot_dir . "/isoimage/");
	die "could not copy dists install pool preseed to $chroot_dir/isoimage: $!\n" unless $rc == 0;

	# save the version and codename of linux
	saveversioncodename ();
	
	# save the squashfs file name
	# this must only be done after the squashfs file has been extracted
	# as unsquashfs wants an empty directory to extract to
	savesquashfsvars();
	
	# umount cdrom
	chdir "/root";
	umountcdrom;

	# make a directory /chrootenvironment
	# so that init-linux can determine if
	# it is running in the chroot environment
	make_path "$chroot_dir/chrootenvironment" or die "Could not make directory $chroot_dir/chrootenvironment: $!\n";
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
	my ($upgrade, $packages) = @_;

	# get codename
	open CDN, "<", "$chroot_dir/isoimage/codename.txt" or die "could not open $chroot_dir/isoimage/codename.txt: $!\n";
	my $codename = <CDN>;
	chomp($codename);
	close CDN;
	print "code name is: $codename\n";


	# generate chroot_dir/etc/apt/sources.list
	# and chroot_dir/etc/sources.list.d/debhome.list
	setaptsources ($codename);

	# ubuntu-install will copy xwindows themes and icons to /usr/share
	# if themes.tar.xz and icons.tar.xz are found
	my $rc;

	#############################################################################################
	# enter the chroot environment
	#############################################################################################

	# install apps in the chroot environment
	# svn and debhome must be accessible at this point
	print "dochroot: calling bindall\n" if $debug;
	bindall ();
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
	do {print "parameters: $parameters\n" if $parameters;} if $debug;

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
	unbindall ();

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
# and if version >= 24.04 the all *.squashfs must be copied
# to casper directory
# the global variable $version is set.
# the full iso name is in $chroot_dir/isoimage/version.txt
# parameter passed: none
# returns none
# requirements: none
######################################################
sub getversion {
	
	################################
	# determine the version for grub
	# get the iso name from $chroot_dir/isoimage/isoimage.txt
	################################

	# read the file 
	open ISO, "<", "$chroot_dir/isoimage/version.txt" or die "could not open $chroot_dir/isoimage/isoimage.txt: $!\n";
	$version = <ISO>;
	chomp($version);
	close ISO;
	
	return;
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
	findrepo($source);

	# mount the destination parition
	$rc = mountdevice($label, "/mnt/$label", "rw", "true");

	# source found, copy it
	# options for debug
	my $options = "";
	$options = " -v " if $debug;
	
	$rc = system("cp -dR -T $options $source /mnt/$label" . "$rootdir");
	die "Could not copy $source to /mnt/$label" . "$rootdir: $!\n" unless $rc == 0;

	#un mount the destination drive
	$rc = system("umount /mnt/$label");
	die "Could not umount $label: $!\n" unless $rc == 0;
}
	
#################################################
# this sub sets up grub and installs it.
# this is only necessary for partition 1
# the call: installgrub(partition_path)
# requires: svn and LINUXLIVE
#################################################
sub installgrub {
	
	##########################################################################################################
	# export the grub.cfg for mbr and uefi and edit grub only for partition 1
	##########################################################################################################
	my ($partition_path) = @_;
	my $rc;

	# export grub
	$rc = system("svn export --force --depth files file://$svn/root/my-linux/livescripts/grub/vfat/mbr/ " . $chroot_dir . "/boot/grub/");
	die "Could not export mbr grub\n" unless $rc == 0;
	$rc = system("svn export --force --depth files file://$svn/root/my-linux/livescripts/grub/vfat/efi/ " . $chroot_dir . "/boot/EFI/grub/");
	die "Could not export efi grub\n" unless $rc == 0;
	
	# now edit grub.cfg with the new version no.
 	# edit mbr grub and set version
    
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
	print "installgrub: $device\n";
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
	my ($label, $casper) = @_;
	
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
	print $label . " is: $partition_path\n" if $debug;
	
	# check if the partition, LINUXLIVE  is mounted at any location
	# un mount it if it is mounted
	my $devandmtpt = `grep "$partition_path" /etc/mtab | cut -d " " -f 1-2`;
	chomp($devandmtpt);
	my ($dev, $mtpt) = split /\s+/, $devandmtpt;

	# if label LINUXLIVE|UBUNTU is mounted, un mount it
	if (defined $mtpt) {
		print "$label mounted at: $mtpt\n" if $debug;
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
	makefs() unless -f "$chroot_dir/dochroot/$squashfsfilename";

	# empty /chroot1/boot
	# this must be done after makefs, the config-xxxx-generic file
	# must be in the filesystem.squashfs for initramfs to work
	# during linux installation
	chdir $chroot_dir . "/boot";
	system ("rm -rf *");

	# mount the partition LINUXLIVE/UBUNTU under 
	# chroot/boot, it was unmounted before chroot
	$rc = mountdevice($label, "$chroot_dir/boot", "rw", "true");

	# make casper dir if it does not exist
	if ( -d $casper) {
		# clean directory
		system("rm -rf $casper");
	}
	# create directory
	make_path $casper;
	
	###################################################################
	# note on ubuntu version
	# prior to 24.04 only filesystem.squashfs existed in casper
	# from 24.04 onwards minimal.squashfs and many other .squashfs
	# files exist in casper. All are required in the live system.
	#
	# if ubuntu version is < 24.04
	# createchroot now makes $chroot_dir/oldboot and
	# copies vmlinuz and initrd from the cdrom to oldboot.
	# if an upgrade of the kernel was done liveinstall
	# will have copied the newer vmlinuz and initrd to oldboot
	# should have done this originally.
	# vmlinuz and initrd must be copied to casper
	#
	# else if ubuntu version is >= 24.04
	# the original initrd and vmlinuz must be used
	# all the *.squashfs files must be copied to $casper
	# an upgrade does not work with version >= 24.04
	##################################################################
	
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
	make_path $chroot_dir . "/boot/boot";
		
	# setup and install grub if this is the first partition
	installgrub($partition_path);
	
	# set grub colours
	editgrub();
	
	# make the persistence file
	chdir $casper;
	system("dd if=/dev/zero of=writable bs=1M count=3000");
	system("mkfs.ext4 -v -j -F writable");

	# so chroot1/boot can be unmounted
	chdir "/root";
	
	
	$rc = system("cp -vf $chroot_dir/dochroot/$squashfsfilename " . $casper);
	die "Could not move /tmp/$squashfsfilename to $casper\n" unless $rc == 0;
	
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

	# die if no /choot and it is not being created
	if (! -d $chroot_dir) {
		die "chroot environment does not exist\n" unless $isoimage;
	}
	
	# restore squashfs file name and version if chroot environment is not
	# being created.
	do  {
		restoresquashfsvars();
		getversion();
	} unless $isoimage;

	# some short cuts depending on the parition number
	my $casper = $chroot_dir . "/boot/casper";
	my $label = "LINUXLIVE";
		
	# if p or u given then set chrootuse
	# if chroot does not exist then set chroot
	do {print "packages: $packages\n" if $packages;
	    print "upgrade:\n" if $upgrade;} if $debug;
	
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

	createchroot($isoimage, $debhomepath, $svnpath) if $isoimage;
	print "initialise: debhomepath = $debhomepath svnpath = $svnpath\n" if $debug;

	# -i needs svn and linuxlive
	# -u -p -e need svn and debhome
	# -c needs cdrom
	# -m needs nothing

	if ($upgrade or $packages or $dochroot) {
		# svn and debhome needed
		findrepo($svnpath, $svn);

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
		dochroot($upgrade, $packages);
		
	} elsif (($doinstall or $makefs) and (! -d "$chroot_dir/dochroot")) {
		# dochroot must be done if directory dochroot does not exist
		dochroot($upgrade, $packages);
	}
	
	
	# make filesystem.squashfs if not installing
	makefs() if $makefs;

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
	installfs($label, $casper) if $doinstall;

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
	print "-L reset svn and debhome links to defaults and exit\n";
	print "-V check version and exit\n";
	print "-Z set debug flag to 1\n";
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

getopts('mic:ep:hus:S:d:M:R:VD:T:LZ');

# turn on debug info if flag set
$debug = 1 if $opt_Z;

# reset links for svn and debhome to original
# before loading links.
if ($opt_L) {
	# restore links before links are loaded
	restoremainlinks();
	# now save the links
	# to the rc file
	savelinks($svnpathoriginal, $debhomepathoriginal);

	# exit
	exit 0;
}
# read config file if it exists
# to set links for svn and debhome
loadlinks();
print "main: svnpathoriginal = $svnpathoriginal debhomepathoriginal = $debhomepathoriginal\n" if $debug;

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

# save the links if they have changed
if ($opt_s or $opt_d) {
	# save the changed links
	$svnpathoriginal = $svnpath;
	$debhomepathoriginal = $debhomepath;

	# restore links
	restoremainlinks();
	savelinks($svnpath, $debhomepath);
}


print "main: svnpath = $svnpath debhomepath = $debhomepath\n" if $debug;

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
print "main: svnpathoriginal = $svnpathoriginal debhomepathoriginal = $debhomepathoriginal\n" if $debug;
restoremainlinks;
