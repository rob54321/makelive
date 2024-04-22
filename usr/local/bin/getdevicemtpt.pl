#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;

my $debug = 0;

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
	my $refdevicemtpt = shift @_;
	
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
		$refdevicemtpt->[0] = $device;
		$refdevicemtpt->[1] = $mtpt;
		print "device = $device mount point = $mtpt\n" if $debug;
	} else {
		# leave array devicemtpt empty
		print "no device found\n" if $debug;
	}
}

# main entry
my $path = "/a/b/c/mnt/d/e/kad64/e/f/g/svn";

my @devicemtpt;
getdevicemtpt($path, \@devicemtpt);

if (@devicemtpt) {
	print "device = $devicemtpt[0] mount point = $devicemtpt[1]\n";
} else {
	print "device not found\n";
}
