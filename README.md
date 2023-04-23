# 这是什么
适用于小硬盘 ipv6 only VPS的 Debian 精简 DD 镜像，使用 github action 每月从官方源构建一次

理论上通过 `cloud-init` 下发网络配置的 VPS 都可以使用，目前只在 Scaleway 上测试过

- 支持 EFI 和 BIOS 启动
- 根目录占用约180MB（精简掉了帮助文档等，使用 Btrfs 文件系统压缩）
- 自动根据硬盘大小扩容（最小需要420M的硬盘）
- 使用 [wgcf](https://github.com/ViRb3/wgcf) 自动申请并启用 Cloudflare WARP ipv4
- 默认使用 bbr 拥塞控制

# 怎么用

恢复模式， `/dev/vda` 为目标盘，如果不确定可用 `lsblk` 查找

``` bash
wget https://awawa.eu.org/debian_stable.img.gz -qO- |gzip -d|dd of=/dev/vda bs=1M status=progress conv=sparse oflag=dsync
```

一定不要DD挂载中的系统盘，大概率会启动不了

请使用恢复模式，或者 `pivot_root` 到内存再操作

考虑到 v6 鸡不好访问 GitHub Release ，用 cf 中转了下<br>~~O皇你不要过来啊~~

如果能自行解决 v4 访问也可以从 Release 下载

# 坑
大部分是 Btrfs 带来的:

- Btrfs 在数据库 io 上表现很糟糕，一定要用数据库的话记得关掉 CoW `chattr +C /数据库/文件` 。<br>
~~不会真的有人想在 1-2G 硬盘的小鸡上跑个 MySQL 吧~~

- Btrfs 支持 swap 文件，同样需要关掉 CoW。 避免麻烦镜像中预留了 128M 的 swap 分区


- 为了在小硬盘上使用 Btrfs ，格式化的时候使用了 [mixed mode](https://btrfs.readthedocs.io/en/latest/mkfs.btrfs.html#options) , <br>
官方文档不建议在5G以上的硬盘使用（影响性能），大硬盘慎用。

想到再写
