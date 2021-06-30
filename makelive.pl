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

# this sub sets up grub and installs it.
# this is only necessary for partition 1
# the call: grubsetup(ubuntu_iso_name, chroot_directory, partition_path)
sub grubsetup {
	##########################################################################################################
	# export the grub.cfg for mbr and uefi and edit grub only for partition 1
	##########################################################################################################
	my ($ubuntuiso, $chroot_dir, $partition_path) = @_;
	
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
	# rename macrium file to stop only macrium_pe booting
	system("mv " . $chroot_dir . "/boot/EFI/Microsoft/Boot/bootmgfw.efi "
	             . $chroot_dir . "/boot/EFI/Microsoft/Boot/bootmgfw.efi.old")
	             if -e $chroot_dir . "/boot/EFI/Microsoft/Boot/bootmgfw.efi";

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
# sub to setup partition 1. This is the ubuntu-mate
# partition. Filesystem must be built.
# ubuntu-mate iso must be mounted
# parameters passed:
# setparition(ubuntuiso-name, chroot-directory, packages, part_no)
####################################################
sub setpartition {
	my ($ubuntuiso, $chroot_dir, $upgrade, $packages, $part_no)  = @_;

	# hash part parameters: containing parameters that are partition dependent
	my %pparam = ("1" => {"casper"   => "$chroot_dir/boot/casper",
	                      "label"    => "MACRIUM"},
	              "2" => {"casper"   => "$chroot_dir/boot/casper2",
				          "label"    => "UBUNTU"});

	# some short cuts
	my $casper = $pparam{$part_no}->{"casper"};
	my $label = $pparam{$part_no}->{"label"};
	print $label . " " . $casper . "\n";
	
	# check MACRIUM ad64 is attached
	my $rc = system("blkid -L ad64 > /dev/null");
	my $rc1 = system("blkid -L " . $label . " > /dev/null");
	die $label . " and ad64 must be attached\n" unless ($rc == 0 and $rc1 == 0);

	# get partition_path of MACRIUM ex: /dev/sda1
	my $partition_path = `blkid -L $label`;
	chomp $partition_path;
	print $label . " is: $partition_path\n";
	
	# check if the partition is mounted else where
	# un mount it if it is mounted
	my $devandmtpt = `grep "$partition_path" /etc/mtab | cut -d " " -f 1-2`;
	chomp($devandmtpt);
	my ($dev, $mtpt) = split /\s+/, $devandmtpt;
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
	system("unsquashfs -d " . $chroot_dir . " /mnt/cdrom/casper/filesystem.squashfs");

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
	# mount the partition under chroot/boot if not mounted
	$rc = system("findmnt " . $chroot_dir . "/boot");
	system("mount -L " . $label . " " . $chroot_dir . "/boot") unless $rc == 0;
	
	# make casper dir if it does not exist
	if ( -d $casper) {
		# clean directory
		chdir $casper;
		unlink glob "*.*";
	} else {
		# create directory
		mkdir $casper;
	}
	
	# copy new vmlinuz and initrd if upgrade option was given
	if ($upgrade eq "\"upgrade\"") {
		# copy vmlinuz and initrd.img from host
		# get host version
		my $host_version = `uname -r`;
		chomp $host_version;
		system("cp -vf /boot/vmlinuz-" . $host_version . " " . $casper . "/vmlinuz");
		system("cp -vf /boot/initrd.img-" . $host_version . " " . $casper . "/initrd");
	} else {
		# for no upgrade use vmlinuz initrd from the iso image
		system("cp -vf /mnt/cdrom/casper/vmlinuz /mnt/cdrom/casper/initrd " . $casper);
	}

	# copy pool and install files for ubuntu mate
	chdir "/mnt/cdrom";
	system("cp -dR dists install pool preseed " . $chroot_dir . "/boot/");
	
	
	# make the persistence file
	chdir $casper;
	system("dd if=/dev/zero of=writable bs=1M count=3000");
	system("mkfs.ext4 -v -j -F writable");
	
	# write new filesystem.squashfs to boot directory
	chdir "/mnt/hdint";
	system("mksquashfs " . $chroot_dir . " /mnt/hdint/filesystem.squashfs -e boot");
	system("mv -vf filesystem.squashfs " . $casper);
	
	# un mount /mnt/cdrom
	system("umount /mnt/cdrom");
	
	# setup and install grub if this is the first partition
	grubsetup($ubuntuiso, $chroot_dir, $partition_path) if $part_no == 1;
	
	# umount chroot boot
	system("umount " . $chroot_dir . "/boot");
	$rc = system("findmnt " . $chroot_dir . "/boot");
	print "count not umount " . $chroot_dir . "/boot\n" if $rc == 0;
}

sub usage {
	print "-i ubuntu iso full name\n";
	print "-c chroot directory\n";
	print "-u do a full-upgrade\n";
	print "-P partition no 1 or 2\n";
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
our($opt_u, $opt_i, $opt_c, $opt_p, $opt_h, $opt_P);

getopts('i:c:p:huP:');

usage() if $opt_h;

my $ubuntuiso = $opt_i or die "ubuntu iso name required\n";
#check if ubuntuiso exists
die "$ubuntuiso does not exist\n" unless -f $ubuntuiso;

# check if partition number given and must be 1 or 2
die "Partition no 1 or 2 must be given\n" unless $opt_P;
die "Partition no must be 1 or 2\n" unless ($opt_P == 1 or $opt_P == 2);

# the chroot directory must not exist
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
setpartition($ubuntuiso, $chroot_dir, $upgrade, $packages, $opt_P);
