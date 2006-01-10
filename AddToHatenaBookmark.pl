# A plugin for posting an entry as a hatena bookmark
#
# $Id$
#
# This software is provided as-is. You may use it for commercial or 
# personal use. If you distribute it, please keep this notice intact.
#
# Copyright (c) 2006 Hirotaka Ogawa
#
package MT::Plugin::AddToHatenaBookmark;
use strict;
use MT;
use base 'MT::Plugin';
use vars qw($VERSION);
$VERSION = '0.01';

my $plugin = MT::Plugin::AddToHatenaBookmark->new({
    name => 'AddToHatenaBookmark',
    description => 'This plugin enables MT to post a hatena bookmark entry when updating published entries or adding newly published entries.',
    doc_link => 'http://as-is.net/blog/archives/001089.html',
    author_name => 'Hirotaka Ogawa',
    author_link => 'http://profile.typekey.com/ogawa/',
    version => $VERSION,
    blog_config_template => \&template,
    settings => new MT::PluginSettings([
					['hatena_username', { Default => '' }],
					['hatena_password', { Default => '' }]
					])
    });
MT->add_plugin($plugin);

my $mt = MT->instance;
MT->add_callback((ref $mt eq 'MT::App::CMS' ? 'AppPostEntrySave' : 'MT::Entry::post_save'),
		 5, $plugin, \&post);

use MT::Util qw(encode_html);
use MT::Log;
use MT::I18N;
use XML::Atom::Entry;
use XML::Atom::Client;

sub post {
    my ($eh, $app, $obj) = @_;
    return if !UNIVERSAL::isa($obj, 'MT::Entry') || $obj->status != MT::Entry::RELEASE();

    my $blog_id = $obj->blog_id;

    my $config = $plugin->get_config_hash("blog:$blog_id") or return;
    my $username = $config->{hatena_username} or return;
    my $password = $config->{hatena_password} or return;

    my $comment = $obj->keywords ? keywords2comment($obj->keywords) : '';
    if ($comment) {
	my $enc = MT::ConfigMgr->instance->PublishCharset || 'utf-8';
	$comment = MT::I18N::encode_text($comment, $enc, 'utf-8');
    }

    my $link = XML::Atom::Link->new;
    $link->type('text/html');
    $link->rel('related');
    $link->href($obj->permalink);

    my $entry = XML::Atom::Entry->new;
    $entry->title('dummy');
    $entry->add_link($link);
    $entry->summary($comment) if $comment;

    my $hatena = XML::Atom::Client->new;
    $hatena->username($username);
    $hatena->password($password);
    my $editURI = $hatena->createEntry('http://b.hatena.ne.jp/atom/post', $entry);

    my $log = MT::Log->new;
    $log->blog_id($blog_id);
    $log->message($editURI ?
		  'Hatena request suceeded: ' . $editURI :
		  'Hatena request failed: ' . $hatena->errstr);
    $log->save or die $log->errstr;
}

sub keywords2comment {
    my ($str) = @_;
    return '' unless $str;
    $str =~ s/\#.*$//g;
    $str =~ s/(^\s+|\s+$)//g;
    return '' unless $str;

    my $comment = '';
    if ($str =~ m/[;,|]/) {
	# tags separated by non-whitespaces
	while ($str =~ m/(\[[^]]+\]|"[^"]+"|'[^']+'|[^;,|]+)/g) {
	    my $tag = $1;
	    $tag =~ s/(^[\["'\s;,|]+|[\]"'\s;,|]+$)//g;
	    $comment .= '[' . $tag . ']' if $tag;
	}
    } else {
	# tags separated by whitespaces
	while ($str =~ m/(\[[^]]+\]|"[^"]+"|'[^']+'|[^\s]+)/g) {
	    my $tag = $1;
	    $tag =~ s/(^[\["'\s]+|[\]"'\s]+$)//g;
	    $comment .= '[' . $tag . ']' if $tag;
	}
    }
    $comment;
}

sub template {
    my $tmpl = <<'EOT';
<p>This plugin enables MT to post a hatena bookmark entry when updating published entries or adding newly published entries.</p>

<p>For more details, see <a href="http://as-is.net/blog/archives/001089.html">"AddToHatenaBookmark Plugin - Ogawa::Memoranda"</a>.</p>

<div class="setting">
<div class="label"><label for="hatena_username">Hatena Username:</label></div>
<div class="field">
<input name="hatena_username" id="hatena_username" size="20" value="<TMPL_VAR NAME=HATENA_USERNAME ESCAPE=HTML>" />
</div>
</div>
<div class="setting">
<div class="label"><label for="hatena_password">Hatena Password:</label></div>
<div class="field">
<input type="password" name="hatena_password" id="hatena_password" size="20" value="<TMPL_VAR NAME=HATENA_PASSWORD ESCAPE=HTML>" />
</div>
</div>
EOT
}

1;
