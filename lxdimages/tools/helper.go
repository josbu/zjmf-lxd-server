package tools

func UseYum(distro, version string) bool {
	if distro == "oracle" && version == "7" {
		return true
	}
	if distro == "amazonlinux" && version == "2" {
		return true
	}
	return false
}

func UseDnf(distro, version string) bool {
	if distro == "oracle" && version != "7" {
		return true
	}
	if distro == "amazonlinux" && version == "2023" {
		return true
	}
	if distro == "centos" || distro == "fedora" || distro == "almalinux" || distro == "rockylinux" {
		return true
	}
	return false
}

