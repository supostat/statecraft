// Progressive enhancement only: every flow works without this file.
// The user switcher submits on change; the visible Switch button stays as
// the no-JS path (rack_test clicks it).
document.addEventListener("change", function (event) {
  var form = event.target.closest("form[data-autosubmit]");
  if (form) form.requestSubmit();
});
