#!/usr/bin/perl

use strict;
use warnings;

#######################################################
# this script makes a live system on hdd /dev/sdX
# where X is the letter for the drive.
# The drive must have been paritioned:
# /dev/sdX1 8g      vfat     label = MACRIUM
# /dev/sdX2 8g      vfat     label= UBUNTU  UUID=4444-4444
# /dev/sdX3 rest    ntfs     label = ssd
# Macrium Reflect 7 must have been installed into partition 1.
#
# Command line parameters:
# makelive.pl ubuntuisoname /dev/sdX partition-no
# partition 1 and 2 have different installation.
# partition 1 has filesystem built
# partition 2 has filesystem copied from iso image.
#
#######################################################

# this sub determines the version
# which will be used for grub
sub getversion {
	################################
	# determine the version for grub
	################################
	my $ubuntuiso = shift;

	# get version
	# names could be ubuntu-21.04-desktop-amd64.iso
	# or             ubuntu-mate-21.04-desktop-amd64.iso
	
	my $version = (split /-/, $ubuntuiso)[1];

	# check if version is a digit
	if ($version !~ /^(\d+)/) {
		# not a digit, must be the next field
		$version = (split /-/, $ubuntuiso)[2];
		
		# if still not a version, prompt for version
		if ($version !~ /^\d+/) {
			# still not a digit, prompt
			print "Can't determine version, enter version\n";
			$version = <STDIN>;
		}
	}
	return $version;
}

####################################################
# sub to setup partition 1. This is the ubuntu-mate
# partition. Filesystem must be built.
# ubuntu-mate iso must be mounted
# parameters passed:
# setparition1(chroot-directory, path-to-device)
####################################################
sub setpartition1 {
	my $chroot-dir = shift;
	my $device = shift;
	
	# unsquash filesystem.squashfs to the chroot directory
	system("unsquashfs -d $chroot-dir /mnt/cdrom/casper/filesystem.squashfs");
	
	# copy other files
	system("cp /etc/resolv.conf /etc/hosts " . $chroot-dir . "/etc/");
	
	# copy etc/apt files
	chdir "/etc/apt";
	system("cp -a trustedgpg trusted.gpg.d sources.list " . $chroot-dir . "/etc/apt/");
	
	# copy from subversion
	system("svn --force export --depth files file:///mnt/svn/root/my-linux/livescripts " . $chroot-dir . "/usr/local/bin/");
}
##################
# Main entry point
##################

# command line parameters
# makelive.pl ubuntuiso-name chroot-directory path-to-hdd partition-no
# get command line argument
# this is the name of the ubuntu iso image
my $ubuntuiso = $ARGV[0];

my $version = getversion($ubuntuiso);

print "$version\n";

# mount ubuntu iso image at /mnt/cdrom
system("mount " . $ubuntuiso . " /mnt/cdrom -o ro");


