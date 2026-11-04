import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  submitDescription(event) {
    if (
      !event.target.matches("input[data-category-suggestion-target~='name']") ||
      event.isComposing ||
      event.altKey ||
      event.ctrlKey ||
      event.metaKey ||
      event.shiftKey
    ) {
      return;
    }

    // Submit after the combobox handles Enter on keydown and locks its selection.
    event.target.form.requestSubmit();
  }
}
