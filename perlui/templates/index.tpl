[% INCLUDE header.tpl %]
<form action="pollResult.pl">
 <input type="hidden" name="test" value="standard" />
 Domenenavn: <input type="text" name="host" value="[% host %]"/> <br />
 <input type="button" value="Test domene" onClick="load();" />
 <span id="test"></span> </br >
 <p>Versjon: [% version %]</p>
[% INCLUDE footer.tpl %]
