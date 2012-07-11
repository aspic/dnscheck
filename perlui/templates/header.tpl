<!DOCTYPE html>
<html>
  <head>
    <title>[% title %]</title>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <script type="text/javascript" src="js/perlui.js"></script>
    <script type="text/javascript" src="js/collapseable.js"></script>
    <link rel="stylesheet" type="text/css" href="css/style.css" />
  </head>
 <body>
 <h1>Domain tester</h1>
 <ul class="menu">
  <li><a href="index.pl?type=standard">[% lng.domain_test %]</a></li>
  <li><a href="index.pl?type=undelegated">[% lng.undelegated_domain_test %]</a></li>
  <li style="float: right;">
   [% lng.language %]:
   <form>
    <select name="locale" id="locale_select" onChange="load_locale();">
     [% FOREACH key IN locales.keys %]
      <option value="[% key %]" [% 'selected="SELECTED"' IF key == locale %]>
       [% locales.$key %]
      </option>
     [% END %]
    </select>
    <noscript>
     [% IF id %]
      <!-- Carry through to get back to the test result -->
      <input type="hidden" name="test_id" value="[% id %]" />
     [% END %]
     <input type="submit" value="[% lng.btn_save %]">
    </noscript>
   </form>
  </li>
 </ul>
