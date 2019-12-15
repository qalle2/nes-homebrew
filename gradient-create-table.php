<?PHP

$ympyra = 2*3.14159;
echo "SiniTaul:";
for ($i=0; $i<256; $i++) {
	$a = 115 + floor(sin($i/256*$ympyra)*100);
	if ($i%16==0) echo "\ndb ";
	echo "$" . substr("0" . strtoupper(dechex($a)), -2);
	if ($i%16<15) echo ",";
}

?>