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

#######################################################
# this sub determines the version
# which will be used for grub
# parameters passed: getversion(full-path-to-iso)
######################################################
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
# setparition1(ubuntuiso-name, chroot-directory, path-to-device)
####################################################
sub setpartition1 {
	my ($ubuntuiso, $chroot_dir, $dev_path)  = @_;

	# mount ubuntu iso image at /mnt/cdrom
	system("mount " . $ubuntuiso . " /mnt/cdrom -o ro");
	
	# mount the dev under chroot/boot if not mounted
	my $rc = system("grep -q " . $dev_path . "1 /etc/mtab");
	system("mount -L MACRIUM " . $chroot_dir . "/boot") unless $rc == 0;
	
	# unsquash filesystem.squashfs to the chroot directory
	# the directory must not exist
	# system("unsquashfs -d $chroot_dir /mnt/cdrom/casper/filesystem.squashfs");
	
	# copy other files
	system("cp /etc/resolv.conf /etc/hosts " . $chroot_dir . "/etc/");
	system("cp /mnt/cdrom/casper/vmlinuz /mnt/cdrom/casper/initrd " . $chroot_dir . "/boot/");
	
	# un mount /mnt/cdrom
	system("umount /mnt/cdrom");
	
	# copy etc/apt files
	chdir "/etc/apt";
	system("cp -a trusted.gpg trusted.gpg.d sources.list " . $chroot_dir . "/etc/apt/");
	
	# copy from subversion
	system("svn --force export --depth files file:///mnt/svn/root/my-linux/livescripts " . $chroot_dir . "/usr/local/bin/");
	system("svn --force export --depth files file:///mnt/svn/root/my-linux/livescripts/grub/vfat/mbr/grub.cfg " . $chroot_dir . "/boot/grub/");
    system("svn --force export --depth files file:///mnt/svn/root/my-linux/livescripts/grub/vfat/efi/grub.cfg " . $chroot_dir . "/boot/EFI/grub/");
    
    # now edit grub.cfg with the new version no.
    # edit mbr grub and set version
    # get version
    my $version = getversion($ubuntuiso);
    
	chdir $chroot_dir . "/boot/grub";
	system("sed -i -e 's/ubuntu-version/$version/' grub.cfg");
	chdir $chroot_dir . "/boot/EFI/grub";
	system("sed -i -e 's/ubuntu-version/$version/' grub.cfg");
	
	# edit fstab in chroot for ad64 which includes debhome
	chdir $chroot_dir . "/etc";
	system("sed -i -e '/LABEL=ad64/d' fstab");
	system("sed -i -e 'a \ LABEL=ad64 /mnt/ad64 ext4 defaults,noauto 0 0' fstab");
	
	# make directories in chroot
	chdir $chroot_dir . "/mnt";
	mkdir "ad64" unless -d "ad64";
	# make link
	unlink "hdd" if -l "hdd";
	system("ln -s ad64 hdd");
	
	
}
##################
# Main entry point
##################

# command line parameters
# makelive.pl ubuntuiso-name chroot-directory path-to-hdd partition-no
# get command line argument
# this is the name of the ubuntu iso image
my ($ubuntuiso, $chroot_dir, $dev_path, $part_no) = @ARGV;

# setup correct partition no
if ($part_no == 1) {
	# setup partition 1
	setpartition1($ubuntuiso, $chroot_dir, $dev_path);
} elsif ($part_no == 2) {
	# setup partition 2
}
