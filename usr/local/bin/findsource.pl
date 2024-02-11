#!/usr/bin/perl

use strict;
use warnings;
use File::Basename;

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
	# which is rw
	$options = "rw" unless ($options);

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
	return if -d $source;

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
	LOOP: foreach my $bdev (@blkdev) {
		foreach my $dir (@pathelements) {
print "bdev $bdev    path elements $dir\n";
			if ("$dir" eq "$bdev") {
				$device = $bdev;
				last LOOP;
			}
		}
		$count++;
	}
print "device = $device count = $count\n";
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
		for(my $i=0; $i<$count; $i++) {
			# append elements to make path
			$mountpoint = $mountpoint . "/" . $pathelements[$i];
		}
print "device = $device mountpoint = $mountpoint\n";
		
		mountdevice($device, $mountpoint, "rw");
		# check if the source exists
		if ( -d $source ) {
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

findsource("/mnt/ad64/livesystem");
