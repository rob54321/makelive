#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Std;

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
# setparition1(ubuntuiso-name, chroot-directory)
####################################################
sub setpartition1 {
	my ($ubuntuiso, $chroot_dir, $packages)  = @_;
	
	# get dev_path ex: /dev/sda1
	my $dev_path = `blkid -L MACRIUM`;
	chomp $dev_path;
	print "$dev_path\n";

	# mount ubuntu iso image at /mnt/cdrom
	my $rc = system("findmnt /mnt/cdrom");
	system("mount " . $ubuntuiso . " /mnt/cdrom -o ro") unless $rc == 0;
	

	# unsquash filesystem.squashfs to the chroot directory
	# the directory must not exist
	system("unsquashfs -d $chroot_dir /mnt/cdrom/casper/filesystem.squashfs");

	# delete all files in $chroot_dir / boot
	system("rm -rf " . $chroot_dir . "/boot");
	mkdir $chroot_dir . "/boot";
	
	# edit fstab in chroot for ad64 which includes debhome
	chdir $chroot_dir . "/etc";
	system("sed -i -e '/LABEL=ad64/d' fstab");
	system("sed -i -e 'a \ LABEL=ad64 /mnt/ad64 ext4 defaults,noauto 0 0' fstab");

	# mount the dev under chroot/boot if not mounted
	$rc = system("findmnt " . $chroot_dir . "/boot");
	system("mount -L MACRIUM " . $chroot_dir . "/boot") unless $rc == 0;
	
	# copy other files
	system("cp /etc/resolv.conf /etc/hosts " . $chroot_dir . "/etc/");
	mkdir $chroot_dir . "/boot/casper" unless -d $chroot_dir . "/boot/casper";
	system("cp /mnt/cdrom/casper/vmlinuz /mnt/cdrom/casper/initrd " . $chroot_dir . "/boot/casper/");
	
	# un mount /mnt/cdrom
	system("umount /mnt/cdrom");
	
	# copy etc/apt files
	chdir "/etc/apt";
	system("cp -a trusted.gpg trusted.gpg.d sources.list " . $chroot_dir . "/etc/apt/");
	
	# copy from subversion
	system("svn export --force --depth files file:///mnt/svn/root/my-linux/livescripts " . $chroot_dir . "/usr/local/bin/");
	system("svn export --force --depth files file:///mnt/svn/root/my-linux/livescripts/grub/vfat/mbr/ " . $chroot_dir . "/boot/grub/");
    system("svn export --force --depth files file:///mnt/svn/root/my-linux/livescripts/grub/vfat/efi/ " . $chroot_dir . "/boot/EFI/grub/");
    
    # now edit grub.cfg with the new version no.
    # edit mbr grub and set version
    # get version
    my $version = getversion($ubuntuiso);
    
	chdir $chroot_dir . "/boot/grub";
	system("sed -i -e 's/ubuntu-version/$version/' grub.cfg");
	chdir $chroot_dir . "/boot/EFI/grub";
	system("sed -i -e 's/ubuntu-version/$version/' grub.cfg");
	
	
	# make directories in chroot
	chdir $chroot_dir . "/mnt";
	mkdir "ad64" unless -d "ad64";
	# make link
	unlink "hdd" if -l "hdd";
	system("ln -s ad64 hdd");

	# enter the chroot environment
	# install apps in the chroot environment
	system("/usr/local/bin/bindall $chroot_dir");

	system("chroot $chroot_dir /usr/local/bin/liveinstall.sh");
	# install extra apps if there are any
	system("chroot $chroot_dir apt -y install $packages") unless $packages eq "none";

	# for exiting the chroot environment
	system("/usr/local/bin/unbindall $chroot_dir");

	# make the persistence file
	chdir $chroot_dir . "/boot/casper";
	system("dd if=/dev/zero of=writable bs=1M count=3000");
	system("mkfs.ext4 -v -j -F writable");
	
	# write new filesystem.squashfs to boot directory
	chdir "/mnt/hdint";
	system("mksquashfs " . $chroot_dir . " /mnt/hdint/filesystem.squashfs -e boot");
	system("mv -vf filesystem.squashfs " . $chroot_dir . "/boot/casper/");
	
	# rename macrium file to stop only macrium_pe booting
#	chdir $chroot_dir . "/boot/EFI/Microsoft/Boot";
	#system("mv bootmgfw.efi bootmgfw.efi.old") if -e "bootmgfw.efi";
	
	# install grub
	# get device from partition path
	my $device = $dev_path;
	chop $device;
	print "$device\n";
	system("grub-install -v --no-floppy --boot-directory=" . $chroot_dir . "/boot --target=i386-pc " . $device);
	system(" grub-install -v --no-floppy --boot-directory=" . $chroot_dir . "/boot/EFI --efi-directory=" . $chroot_dir . "/boot --removable --target=x86_64-efi " . $device);

	# umount chroot boot nees a little time to finish copying
	system("umount " . $chroot_dir . "/boot");
	$rc = system("findmnt " . $chroot_dir . "/boot");
	print "count not umount " . $chroot_dir . "/boot\n" if $rc == 0;
}

sub usage {
	print "-i ubuntu iso full name\n";
	print "-c chroot directory\n";
	print "-1 for partition 1\n";
	print "-2 for partition 2\n";
	print "-p list of packages to install in chroot in quotes\n";
	exit 0;
}
##################
# Main entry point
##################

# command line parameters
# makelive.pl ubuntuiso-name chroot-directory partition-no
# get command line argument
# this is the name of the ubuntu iso ima
our($opt_i, $opt_c, $opt_p, $opt_h, $opt_1, $opt_2);

getopts('12i:c:p:h');

usage() if $opt_h;

my $ubuntuiso = $opt_i or die "ubuntu iso name required\n";
#check if ubuntuiso exists
die "$ubuntuiso does not exist\n" unless -f $ubuntuiso;

my $chroot_dir = $opt_c or die "chroot directory rquired\n";
die "chroot directory must not exist\n"	if -d $chroot_dir;

# packages may or may not have a value
my $packages;
if ($opt_p) {
	$packages = $opt_p;
} else {
	$packages = "none";
}

# setup correct partition no
if ($opt_1) {
	# setup partition 1
	setpartition1($ubuntuiso, $chroot_dir, $packages);

} elsif ($opt_2) {
	# setup partition 2

}
