# LiveKit

## module bundle file list
### /run/desc
desc 示例
```
name=claymore
version=11.7
service=claymore.service
```

> `service` 字段用来处理`containerStart`及其systemd状态监控

### /run/install
```
post_install() {
    /usr/bin/gtk-query-immodules-2.0 --update-cache
}

pre_upgrade() {
    if (( $(vercmp $2 2.24.20) < 0 )); then
        rm -f /etc/gtk-2.0/gtk.immodules
    fi
}

post_upgrade() {
    post_install
}

pre_remove() {
    rm -f /usr/lib/gtk-2.0/2.10.0/immodules.cache
}
```
待实现