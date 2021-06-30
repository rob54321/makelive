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
# setparition1(ubuntuiso-name, chroot-directory, packages, part_no)
####################################################
sub setpartition1 {
	my ($ubuntuiso, $chroot_dir, $upgrade, $packages, $part_no)  = @_;
	
	# check MACRIUM ad64 is attached
	my $rc = system("blkid -L ad64 > /dev/null");
	my $rc1 = system("blkid -L MACRIUM > /dev/null");
	die "MACRIUM and ad64 must be attached\n" unless ($rc == 0 and $rc1 == 0);

	# get dev_path of MACRIUM ex: /dev/sda1
	my $dev_path = `blkid -L MACRIUM`;
	chomp $dev_path;
	print "MACRIUM is: $dev_path\n";
	
	# check if MACRIUM is mounted else where
	# un mount it if it is mounted
	my $macrium = `grep "$dev_path" /etc/mtab | cut -d " " -f 1-2`;
	chomp($macrium);
	my ($macrium_dev, $mtpt) = split /\s+/, $macrium;
	print "$mtpt\n" if $mtpt;
	system("umount $mtpt") if $mtpt;
	
	# unmount iso image if it is mounted
	# mount ubuntu-mate iso image
	$rc = system("findmnt /mnt/cdrom");
	# umount /mnt/cdrom
	system("umount /mnt/cdrom") if $rc == 0;
	system("mount " . $ubuntuiso . " /mnt/cdrom -o ro");
	

	#####################################################################################
	# copy and edit files to chroot
	#####################################################################################
	# unsquash filesystem.squashfs to the chroot directory
	# the directory must not exist
	system("unsquashfs -d $chroot_dir /mnt/cdrom/casper/filesystem.squashfs");

	# edit fstab in chroot for ad64 which includes debhome
	chdir $chroot_dir . "/etc";
	system("sed -i -e '/LABEL=ad64/d' fstab");
	system("sed -i -e 'a \ LABEL=ad64 /mnt/ad64 ext4 defaults,noauto 0 0' fstab");

	system("cp /etc/resolv.conf /etc/hosts " . $chroot_dir . "/etc/");
	system("cp /etc/network/interfaces " . $chroot_dir . "/etc/network/");

	# make directories in chroot
	chdir $chroot_dir . "/mnt";
	mkdir "ssd" unless -d "ssd";
	mkdir "ad64" unless -d "ad64";
	# make link
	unlink "hdd" if -l "hdd";
	system("ln -s ad64 hdd");

	
	# copy etc/apt files
	chdir "/etc/apt";
	system("cp -dR trusted.gpg trusted.gpg.d sources.list " . $chroot_dir . "/etc/apt/");
	
	# export livescripts from subversion
	system("svn export --force --depth files file:///mnt/svn/root/my-linux/livescripts " . $chroot_dir . "/usr/local/bin/");

	#########################################################################################################################
	# enter the chroot environment
	#########################################################################################################################
	
	# install apps in the chroot environment
	system("/usr/local/bin/bindall $chroot_dir");

	# parameters must be quoted for Bash
	$upgrade = "\"" . $upgrade . "\"";
	$packages = "\"" . $packages . "\"";
	# execute liveinstall.sh in the chroot environment
	system("chroot $chroot_dir /usr/local/bin/liveinstall.sh $upgrade $packages");

	# for exiting the chroot environment
	system("/usr/local/bin/unbindall $chroot_dir");

	# delete all files in $chroot_dir / boot
	system("rm -rf " . $chroot_dir . "/boot");
	mkdir $chroot_dir . "/boot";
	
	#########################################################################################################################
	# copy and edit files to chroot/boot
	#########################################################################################################################
	# mount the MACRIUM under chroot/boot if not mounted
	$rc = system("findmnt " . $chroot_dir . "/boot");
	system("mount -L MACRIUM " . $chroot_dir . "/boot") unless $rc == 0;
	
	# make casper dir if it does not exist
	if ( -d $chroot_dir . "/boot/casper") {
		# clean directory
		chdir $chroot_dir . "/boot/casper";
		unlink glob "*.*";
	} else {
		# create directory
		mkdir $chroot_dir . "/boot/casper";
	}
	
	# copy new vmlinuz and initrd if upgrade option was given
	if ($upgrade eq "\"upgrade\"") {
		# copy vmlinuz and initrd.img from host
		# get host version
		my $host_version = `uname -r`;
		chomp $host_version;
		system("cp -vf /boot/vmlinuz-" . $host_version . " " . $chroot_dir . "/boot/casper/vmlinuz");
		system("cp -vf /boot/initrd.img-" . $host_version . " " . $chroot_dir . "/boot/casper/initrd");
	} else {
		# for no upgrade use vmlinuz initrd from the iso image
		system("cp -vf /mnt/cdrom/casper/vmlinuz /mnt/cdrom/casper/initrd " . $chroot_dir . "/boot/casper/");
	}

	# export the grub.cfg for mbr and uefi
	system("svn export --force --depth files file:///mnt/svn/root/my-linux/livescripts/grub/vfat/mbr/ " . $chroot_dir . "/boot/grub/");
    system("svn export --force --depth files file:///mnt/svn/root/my-linux/livescripts/grub/vfat/efi/ " . $chroot_dir . "/boot/EFI/grub/");

	# copy pool and install files for ubuntu mate
	chdir "/mnt/cdrom";
	system("cp -dR dists install pool preseed " . $chroot_dir . "/boot/");
	
    
    # now edit grub.cfg with the new version no.
    # edit mbr grub and set version
    # get version
    my $version = getversion($ubuntuiso);
    
	chdir $chroot_dir . "/boot/grub";
	system("sed -i -e 's/ubuntu-version/$version/' grub.cfg");
	chdir $chroot_dir . "/boot/EFI/grub";
	system("sed -i -e 's/ubuntu-version/$version/' grub.cfg");
	
	# make the persistence file
	chdir $chroot_dir . "/boot/casper";
	system("dd if=/dev/zero of=writable bs=1M count=3000");
	system("mkfs.ext4 -v -j -F writable");
	
	# write new filesystem.squashfs to boot directory
	chdir "/mnt/hdint";
	system("mksquashfs " . $chroot_dir . " /mnt/hdint/filesystem.squashfs -e boot");
	system("mv -vf filesystem.squashfs " . $chroot_dir . "/boot/casper/");
	
	# rename macrium file to stop only macrium_pe booting
	system("mv " . $chroot_dir . "/boot/EFI/Microsoft/Boot/bootmgfw.efi "
	             . $chroot_dir . "/boot/EFI/Microsoft/Boot/bootmgfw.efi.old")
	             if -e $chroot_dir . "/boot/EFI/Microsoft/Boot/bootmgfw.efi";

	# install grub
	# get device from partition path
	my $device = $dev_path;
	chop $device;
	print "$device\n";
	system("grub-install --no-floppy --boot-directory=" . $chroot_dir . "/boot --target=i386-pc " . $device);
	
	system(" grub-install --no-floppy --boot-directory=" . $chroot_dir . "/boot/EFI --efi-directory="  . $chroot_dir . "/boot --removable --target=x86_64-efi " . $device);

	# un mount /mnt/cdrom
	system("umount /mnt/cdrom");
	
	# umount chroot boot
	system("umount " . $chroot_dir . "/boot");
	$rc = system("findmnt " . $chroot_dir . "/boot");
	print "count not umount " . $chroot_dir . "/boot\n" if $rc == 0;
}

sub usage {
	print "-i ubuntu iso full name\n";
	print "-c chroot directory\n";
	print "-u do a full-upgrade\n";
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
our($opt_u, $opt_i, $opt_c, $opt_p, $opt_h, $opt_1, $opt_2);

getopts('12i:c:p:hu');

usage() if $opt_h;

my $ubuntuiso = $opt_i or die "ubuntu iso name required\n";
#check if ubuntuiso exists
die "$ubuntuiso does not exist\n" unless -f $ubuntuiso;

my $chroot_dir = $opt_c or die "chroot directory rquired\n";
die "chroot directory must not exist\n"	if -d $chroot_dir;


# packages may or may not have a value
my $packages;

if ($opt_p) {
	# make a list between quotes
	$packages = $opt_p;
} else {
	$packages = "";
}

# if and upgrade is selected
# the modules version matching vmlinuz must be installed
# in the chroot environment	
my $host_version;
my $upgrade;

if ($opt_u) {
	# determine version of modules to be installed.
	# the hosts initrd and vmlinuz will be copied to casper
	# of the form 5.11.0-23-generic
	$upgrade = "upgrade";
	$host_version = `uname -r`;
	chomp($host_version);
	$packages = $packages . " linux-modules-" . $host_version . " linux-modules-extra-" . $host_version;
} else {
	# no upgrade
	$upgrade = "";
}

# setup correct partition no
if ($opt_1) {
	# setup partition 1
	setpartition1($ubuntuiso, $chroot_dir, $upgrade, $packages);

} elsif ($opt_2) {
	# setup partition 2

}
