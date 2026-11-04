(function () {
  // Μεταφέρει αυτούσιο το query (code, state, error) στην εφαρμογή. Δεν αποθηκεύει, δεν στέλνει τίποτα αλλού.
  var q = window.location.search || '';
  var target = 'ygeiaforma://oura-callback' + q;
  var back = document.getElementById('back');
  if (back) back.setAttribute('href', target);
  if (!q) {
    var msg = document.getElementById('msg');
    if (msg) msg.textContent = 'Δεν ήρθε απάντηση από την Oura. Ξεκίνα ξανά τη σύνδεση από την εφαρμογή.';
    return;
  }
  // Καθαρίζει τον κωδικό από τη γραμμή διευθύνσεων και το ιστορικό.
  try { window.history.replaceState(null, '', window.location.pathname); } catch (e) {}
  window.location.replace(target);
})();
