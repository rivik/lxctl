package Lxctl::vz2lxc;

use strict;
use warnings;

use Getopt::Long;

use Lxc::object;

use LxctlHelpers::config;

my %options = ();

my $yaml_conf_dir;
my $lxc_conf_dir;
my $root_mount_path;
my $templates_path;
my $vg;

my $rsync_opts;
my $config;

sub migrate_get_opt
{
	my $self = shift;

	GetOptions(\%options, 'fromhost=s', 'remname=s', 'remuser=s', 'remport=s',
		'rootsz=s', 'rsync=s', 'afterstart!', 'createnew!');

	$options{'remuser'} ||= 'root';
	$options{'remport'} ||= '22';
	$options{'afterstart'} //= 0;
	$options{'createnew'} //= 1;
	$options{'rsync'} ||= '';
	$options{'check-script'} ||= '';

	defined($options{'remname'})
		or die "You should specify the name of the VZ container!\n\n";

	defined($options{'fromhost'}) or
		die "To which host should I migrate?\n\n";

	if (!$options{'rootsz'}) {
		my $cmd = "egrep DISKSPACE /etc/vz/conf/$options{'remname'}.conf || du -sk /var/lib/vz/root/$options{'remname'}";
		$options{'rootsz'} = qx(ssh $options{'remuser'}\@$options{'fromhost'} '$cmd');
		($options{'rootsz'}) = ($options{'rootsz'} =~ /(\d+)(?:\:|\s)/);
		# ceil to GiB, lv size may be too small in case of `du` calculation
		$options{'rootsz'} += 1024**2 - ($options{'rootsz'} % 1024**2) if $options{'rootsz'} % 1024**2;
		$options{'rootsz'} .= 'K';
	}
}

sub re_rsync
{
	my $self = shift;

	print "Stopping VZ container $options{'remname'}...\n";
	die "Failed to stop VZ container $options{'remname'}!\n\n"
		if system("ssh $options{'remuser'}\@$options{'fromhost'} vzctl stop $options{'remname'} 1>/dev/null");

	print "Mounting VZ container $options{'remname'}...\n";
	die "Failed to mount VZ container $options{'remname'}!\n\n"
		if system("ssh $options{'remuser'}\@$options{'fromhost'} vzctl mount $options{'remname'} 1>/dev/null");

	print "Re-rsyncing container $options{'contname'}...\n";
	die "Failed to re-rsync root filesystem!\n\n"
		if system("rsync $rsync_opts -e ssh $options{'remuser'}\@$options{'fromhost'}:/var/lib/vz/root/$options{'remname'}/ $root_mount_path/$options{'contname'}/rootfs/");

	print "Unmounting VZ container $options{'remname'}...\n";
	die "Failed to unmount VZ container $options{'remname'}!\n\n"
		if system("ssh $options{'remuser'}\@$options{'fromhost'} vzctl umount $options{'remname'} 1>/dev/null");

}

sub vz_migrate
{
	my $self = shift;

	$rsync_opts = $config->get_option_from_main('rsync', 'VZ_RSYNC_OPTS');
	$rsync_opts ||= "-aH --numeric-ids --exclude '%veid%/proc/*' --exclude '%veid%/sys/*'";
	# remove -e ssh
	$rsync_opts =~ s/-e\h*ssh\h*//;
	$rsync_opts .= ' '.$options{'rsync'};
	$rsync_opts =~ s/%veid%/$options{'remname'}/g;

	if ($options{'createnew'}) {
		die "Failed to create container!\n\n"
			if system("lxctl create $options{'contname'} --empty --rootsz $options{'rootsz'} --save");
	}
	else {
		die "Can't find container!\n\n"
			if system("lxctl list | grep -q $options{'contname'}");
	}

	print "Rsync'ing VZ container...\n";
	my $cmd=qq(rsync $rsync_opts -e ssh $options{'remuser'}\@$options{'fromhost'}:/var/lib/vz/root/$options{'remname'}/ $root_mount_path/$options{'contname'}/rootfs/);
	print "Running $cmd\n";
	print "There were some errors during rsyncing root filesystem. It's definitely NOT okay if it was the only rsync pass.\n\n"
		if system($cmd);
	$self->re_rsync();

	if (-e "$root_mount_path/$options{'contname'}/rootfs/etc/init/openvz.conf") {
		print "Found upstart openvz.conf. Modifying...\n";
		system("sed -i.bak 's/^.*devpts.*\$//' $root_mount_path/$options{'contname'}/rootfs/etc/init/openvz.conf");
	}

	if ($options{'afterstart'} != 0) {
		die "Failed to start container $options{'contname'}!\n\n"
			if system("lxctl start $options{'contname'}");
	}
}

sub migrate_configuration
{
	my $self = shift;

	die "Failed to migrate MTU!\n\n"
		if system("lxctl set $options{'contname'} --mtu \$(ssh $options{'remuser'}\@$options{'fromhost'} \"sed -n 's/^[\\t ]\\+mtu[\\t ]\\+\\([0-9]\\+\\)/\\1/p' /var/lib/vz/private/$options{'remname'}/etc/network/interfaces | awk '{print \$2}'\")");

	my $vz_iface_name = qx(ssh $options{'remuser'}\@$options{'fromhost'} "egrep NETIF /etc/vz/conf/$options{'remname'}.conf");
	($vz_iface_name) = ($vz_iface_name =~ /ifname=([^,"]+)/);
	my $lxc_iface_name = qx(egrep lxc.network.name /var/lib/lxc/$options{'contname'}/config);
	($lxc_iface_name) = ($lxc_iface_name =~ /lxc\.network\.name\h*=\h*(\S+)/);

	if ($lxc_iface_name ne $vz_iface_name) {
		print "Changing $lxc_iface_name to $vz_iface_name\n";
		my $cmd = qq(perl -i.bak -pe 's/\\b(?:$lxc_iface_name)\\b/$vz_iface_name/' /var/lib/lxc/$options{'contname'}/config);
		print "Running $cmd\n";
		die "Failed to migrate iface name!\n\n" if
			system("$cmd");
	}

	print "Clearing $root_mount_path/$options{'contname'}/rootfs/etc/fstab ...\n";
	die "Failed to remove fstab!\n\n" if
		system("mv $root_mount_path/$options{'contname'}/rootfs/etc/fstab $root_mount_path/$options{'contname'}/rootfs/etc/fstab.bak");
}

sub do
{
	my $self = shift;

	$options{'contname'} = shift
		or die "Name the container please!\n\n";

	$self->migrate_get_opt();
	$self->vz_migrate();
	$self->migrate_configuration();
}

sub new
{
	my $class = shift;
	my $self = {};
	bless $self, $class;
	$self->{lxc} = new Lxc::object;
	$root_mount_path = $self->{'lxc'}->get_roots_path();
	$templates_path = $self->{'lxc'}->get_template_path();
	$yaml_conf_dir = $self->{'lxc'}->get_config_path();
	$lxc_conf_dir = $self->{'lxc'}->get_lxc_conf_dir();
	$vg = $self->{'lxc'}->get_vg();

	$config = new LxctlHelpers::config;
	return $self;
}

1;
__END__

=head1 AUTHOR

Anatoly Burtsev, E<lt>anatolyburtsev@yandex.ruE<gt>
Pavel Potapenkov, E<lt>ppotapenkov@gmail.comE<gt>
Vladimir Smirnov, E<lt>civil.over@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Anatoly Burtsev, Pavel Potapenkov, Vladimir Smirnov

This library is free software; you can redistribute it and/or modify
it under the same terms of GPL v2 or later, or, at your opinion
under terms of artistic license.

=cut
