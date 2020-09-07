# paclink-unix has 2 install options

## 1. Minimum (plumin)

This is a light weight paclink-unix install that gives functionality
to use an email client on the Raspberry Pi to compose & send winlink
messages.

##### Installs the following:
* paclink-unix to format email
* [postfix](http://www.postfix.org/)for the email transfer agent
* [mutt](http://www.mutt.org/) or an upstream version of mutt called [NeoMutt](https://neomutt.org/) for the email user agent
* Enables email clients that support Unix movemail (eg. Thunderbird)

## 2. With IMAP server (plu)

* [installs everything in the basic install plus dovecot IMAP mailserver & 2 more email clients](https://github.com/nwdigitalradio/n7nix/blob/master/plu/PACLINK-UNIX_INSTALL.md#install-paclink-unix--dovecot)

This installs functionality to use any [IMAP](https://en.wikipedia.org/wiki/Internet_Message_Access_Protocol) email client & to access
paclink-unix from a browser. It allows using a WiFi device (smart
phone, tablet, laptop) to compose a Winlink message & envoke
paclink-unix to send the message.

##### Installs the following
* paclink-unix to format email
* postfix for the email transfer agent
* [dovecot](https://github.com/nwdigitalradio/n7nix/tree/master/mailserv), IMAP email server
* [hostapdd](https://github.com/nwdigitalradio/n7nix/tree/master/hostap)
to enable a Raspberry Pi 3 to be a virtual access point
* dnsmasq to allow connecting to the Raspbery Pi when it is not
connected to a network
* nodejs to host the control page for paclink-unix
* iptables to enable NAT

## Supported email clients
While any email client that supports IMAP can be used with paclink-unix these clients are directly supported.
* [Claws-mail native Linux email client](https://www.claws-mail.org/)
* [Rainloop web email client](https://www.rainloop.net/)
* [K-9 Mail Android mobile email app](https://k9mail.github.io/)
* [NeoMutt](https://neomutt.org/)