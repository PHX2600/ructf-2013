#!/usr/bin/perl

use Mojolicious::Lite;
use Mojo::Util 'md5_sum';
use DBI;

my $config = plugin 'Config';
helper db => sub {
    return DBI->connect_cached(@{$config->{db_config}});
};

get '/' => sub {
    my $self = shift;
    my $messages = $self->db->selectall_arrayref(q{
            SELECT id, name, data, ts
            FROM message
            WHERE public = 1
            ORDER BY ts DESC
            LIMIT 50
    });
    $self->stash(messages => $messages);
    $self->render;
} => 'index';

post '/register' => sub {
    my $self = shift;
    my ($name, $pass) = $self->param(['login', 'pass']);
    return $self->render_not_found if "${name}${pass}" =~ m/select|union|from|where|insert|order/i;
    my $db = $self->db;
    ($name, $pass) = map $db->quote($_), ($name, $pass);
    eval {
        $db->do(qq{
            INSERT user (name, pass)
            VALUES ($name, $pass)
        });
    };
    return $self->render_not_found if $@;
    $self->flash(register => 'Yes! you are registered!');
    $self->redirect_to('index');
} => 'register_post';

get '/register' => sub {
    shift->render;
} => 'register';

post '/login' => sub {
    my $self = shift;
    my ($name, $pass) = $self->param(['login', 'pass']);
    return $self->render_not_found if "${name}${pass}" =~ m/select|union|from|where|insert|order/i;
    eval {
        if (my $user = $self->db->selectrow_arrayref(qq{
                SELECT id, name FROM user
                WHERE name = '$name' AND pass = '$pass'
        })) {
            $self->session(uid => $user->[0]);
            $self->session(name => $user->[1]);
            return $self->redirect_to('notepad');
        } else {
            $self->flash(login => 'Invalid login/password, please check credentials!');
            return $self->redirect_to('index');
        }
    };
    return $self->render_not_found if $@;
} => 'login';

get '/logout' => sub {
    my $self = shift;
    delete $self->session->{uid};
    $self->redirect_to('index');
} => 'logout';

post '/post' => sub {
    my $self = shift;
    return $self->redirect_to('index') unless my $uid = $self->session('uid');
    return $self->redirect_to('notepad') unless my $data = $self->param('data');
    my $db = $self->db;
    my $name = $self->session('name');
    $data = $db->quote($data);
    my $public = $self->param('public') ? 1 : 0;

    eval {
        $db->do(qq{
            INSERT message (uid, name, public, data)
            VALUES ($uid, '$name', $public, $data)
        });
    };
    return $self->render_not_found if $@;
    $self->redirect_to('notepad');
} => 'post';

get '/notepad' => sub {
    my $self = shift;
    if (my $uid = $self->session('uid')) {
        my $messages = $self->db->selectall_arrayref(qq{
            SELECT id, public, data, ts
            FROM message
            WHERE uid = $uid
            ORDER BY ts DESC
        });
        $self->stash(messages => $messages);
        $self->render;
    } else {
        return $self->redirect_to('index');
    }
} => 'notepad';

app->secret(md5_sum rand . rand);
app->start;

__DATA__

@@ default.css
table {
    width: 850px;
    border: 1px solid black;
    border-collapse: collapse;
}
table td {
    border: 1px solid black;
}
table p {
    max-width: 500px;
    overflow: hidden;
    text-overflow: clip;
    white-space: nowrap;
    font-size: medium;
    color: #303030;
}
.messages {
    text-align: center;
}
body {
    font-family: monospace;
    font-size: large;
}
.content {
    width: 900px;
    margin-left: auto;
    margin-right: auto;
}
.message {
    color: #606060;
}

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
    <head>
        <title>notepad</title>
        <link type="text/css" rel="stylesheet" href="/default.css">
    </head>
    <body>
        <div class="content">
            <%= content %>
        </div>
    </body>
</html>

@@ register.html.ep
% layout 'default';

<form action="<%= url_for 'register_post' %>" method="POST">
    <div><input type="text" name="login"></input> Login</div>
    <div><input type="text" name="pass"></input> Passwowd</div>
    <input type="submit" value="Register"></input>
</form>

@@ index.html.ep
% layout 'default';

% if (my $login = $self->flash('login')) {
    <p class="message"><%= $login %></p>
% }
% if (my $register = $self->flash('register')) {
    <p class="message"><%= $register %></p>
% }
<div class="control">
% unless ($self->session('uid')) {
    <form action="<%= url_for 'login' %>" method="POST">
        <div><input type="text" name="login"></input> Login</div>
        <div><input type="text" name="pass"></input> Passwowd</div>
        <input type="submit" value="Login"></input>
        <a href="<%= url_for 'register' %>">Register</a>
    </form>
% } else {
    <a href="<%= url_for 'logout' %>">Logout (<%= session 'name' %>)</a>
    <a href="<%= url_for 'notepad' %>">My notepad</a>
% }
</div>
<div class="messages">
    <h1>Last messages from public notepads</h1>
    <table>
        <thead>
            <tr>
                <td>#</td>
                <td>Name</td>
                <td>Data</td>
                <td>Timestamp</td>
            </tr>
        </thead>
        <tbody>
            % for my $m (@$messages) {
                <tr>
                    <td><p><%= $m->[0] %></p></td>
                    <td><p><%= $m->[1] %></p></td>
                    <td><p><%= $m->[2] %></p></td>
                    <td><p><%= $m->[3] %></p></td>
                </tr>
            % }
        </tbody>
    </table>
</div>

@@ notepad.html.ep
% layout 'default';

<form action="<%= url_for 'post' %>" method="POST">
        <div><input type="text" name="data"></input> Data</div>
        <div><input type="checkbox" name="public"></input> Public?</div>
        <input type="submit" value="Post"></input>
        <a href="<%= url_for 'logout' %>">Logout (<%= session 'name' %>)</a>
        <a href="<%= url_for 'index' %>">Main</a>
</form>
<div class="messages">
    <h1>My messages</h1>
    <table>
        <thead>
            <tr>
                <td>#</td>
                <td>public</td>
                <td>data</td>
                <td>ts</td>
            </tr>
        </thead>
        <tbody>
            % for my $m (@$messages) {
                <tr>
                    <td><p><%= $m->[0] %></p></td>
                    <td><p><%= $m->[1] %></p></td>
                    <td><p><%= $m->[2] %></p></td>
                    <td><p><%= $m->[3] %></p></td>
                </tr>
            % }
        </tbody>
    </table>
</div>


@@ not_found.html.ep
% layout 'default';

Oops! Hacker detected!

@@ exception.html.ep
% layout 'default';

Oops! Hacker detected!
