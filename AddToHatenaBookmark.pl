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
$VERSION = '0.03';

my $plugin = MT::Plugin::AddToHatenaBookmark->new({
    name => 'AddToHatenaBookmark',
    description => 'This plugin enables MT to post a hatena bookmark entry when updating published entries or adding newly published entries.',
    doc_link => 'http://as-is.net/wiki/AddToHatenaBookmark_Plugin',
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

use MT::Log;
use MT::I18N;
use XML::Atom::Entry;
use XML::Atom::Client;

sub post {
    my ($eh, $app, $obj) = @_;
    return unless $obj->isa('MT::Entry') && ($obj->status == MT::Entry::RELEASE());

    my $blog_id = $obj->blog_id;

    my $config = $plugin->get_config_hash('blog:' . $blog_id) or return;
    my $username = $config->{hatena_username} or return;
    my $password = $config->{hatena_password} or return;

    my $link = XML::Atom::Link->new;
    $link->type('text/html');
    $link->rel('related');
    $link->href($obj->permalink);

    my $entry = XML::Atom::Entry->new;
    $entry->title('dummy');
    $entry->add_link($link);

    my $hatena = XML::Atom::Client->new;
    $hatena->username($username);
    $hatena->password($password);

    my $editURI = $hatena->createEntry('http://b.hatena.ne.jp/atom/post', $entry);
    unless ($editURI) {
	add_log($blog_id, 'createEntry failed: ' . $hatena->errstr);
	return;
    }

    my $entry_old = $hatena->getEntry($editURI);
    unless ($entry_old) {
	add_log($blog_id, 'getEntry failed: ' . $hatena->errstr);
	return;
    }

    my $title_old = $entry_old->title;
    my $summary_old = extract_summary($entry_old);

    my $title_new = $obj->blog->name . ': ' . $obj->title;
    my $summary_new = tags2summary($obj) || keywords2summary($obj->keywords) || '';

    my $enc = MT::ConfigMgr->instance->PublishCharset || 'utf-8';
    $title_new = MT::I18N::encode_text($title_new, $enc, 'utf-8')
	if $title_new;
    $summary_new = MT::I18N::encode_text($summary_new, $enc, 'utf-8')
	if $summary_new;

    my $msg;
    if ($title_old eq $title_new && $summary_old eq $summary_new) {
	$msg = 'updateEntry skipped: ' . $editURI;
    } else {
	my $entry_new = XML::Atom::Entry->new;
	$entry_new->title($title_new);
	$entry_new->summary($summary_new) if $summary_new;

	$msg = $hatena->updateEntry($editURI, $entry_new) ?
	    'updateEntry suceeded: ' . $editURI :
	    'updateEntry failed: ' . $hatena->errstr;
    }
    add_log($blog_id, $msg);
}

sub add_log {
    my ($blog_id, $message) = @_;
    my $log = MT::Log->new;
    $log->blog_id($blog_id);
    $log->message('[' . $plugin->name . '] ' . $message);
    $log->save or die $log->errstr;
}

# extract summary text from a hatena entry
sub extract_summary {
    my ($entry) = @_;
    my $summary = '';
    my $dc = XML::Atom::Namespace->new(dc => 'http://purl.org/dc/elements/1.1/');
    for my $subject ($entry->getlist($dc, 'subject')) {
	$summary .= '[' . $subject . ']';
    }
    $summary;
}

# convert MT keywords to summary text
sub keywords2summary {
    my ($str) = @_;
    return '' unless $str;
    $str =~ s/\#.*$//g;
    $str =~ s/(^\s+|\s+$)//g;
    return '' unless $str;

    my $summary = '';
    if ($str =~ m/[;,|]/) {
	# separated by non-whitespaces
	while ($str =~ m/(\[[^]]+\]|"[^"]+"|'[^']+'|[^;,|]+)/g) {
	    my $tag = $1;
	    $tag =~ s/(^[\["'\s;,|]+|[\]"'\s;,|]+$)//g;
	    $summary .= '[' . $tag . ']' if $tag;
	}
    } else {
	# separated by whitespaces
	while ($str =~ m/(\[[^]]+\]|"[^"]+"|'[^']+'|[^\s]+)/g) {
	    my $tag = $1;
	    $tag =~ s/(^[\["'\s]+|[\]"'\s]+$)//g;
	    $summary .= '[' . $tag . ']' if $tag;
	}
    }
    $summary;
}

# convert MT tags to summary text
sub tags2summary {
    my $entry = shift;
    return '' unless $entry->can('tags');

    my $summary = '';
    for my $tag ($entry->tags) {
	$summary .= '[' . $tag . ']';
    }
    $summary;
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
