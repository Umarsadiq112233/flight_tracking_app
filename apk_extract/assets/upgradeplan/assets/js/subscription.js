var FR24_SUBSCRIPTION = FR24_SUBSCRIPTION || {};

FR24_SUBSCRIPTION = {
    highlightFeature: function(key) {
        var list = document.querySelector('#subscription-list');

        if(list) {
            // Move feature that exists in the top section to the very top of the highlights section.
            var feature = list.querySelector('a[href="#' + key + '"]');

            if(feature) {
                var featureParent = feature.parentNode;
                featureParent.parentNode.removeChild(featureParent);
                var featureParentCloned = featureParent.cloneNode(true);
                list.insertBefore(featureParentCloned, list.firstChild);
                featureParentCloned.classList.add('list__item--highlighted');
                return;
            }
        }

        var bottomFeature = document.getElementById(key);
        var featureTitle = null;

        if(bottomFeature) {
            // Move feature that exists in the longer feature list to the top highlights section.
            var feature = bottomFeature.querySelector('span.subscription-list-overview__item-header');

            if(feature) {
                featureTitle = feature.textContent.replace(' (GOLD-ONLY FEATURE)', '');
            } else {
                // there was no feature, but maybe there is an section header
                var section = bottomFeature.querySelector('span')

                if (section) {
                    featureTitle = section.textContent
                }
            }
        }

        var hiddenListItem = document.querySelector('#hidden-list-item');

        if(hiddenListItem && featureTitle) {
            // Insert the feature from the lower section into the upper section,
            // using a previously hidden list item.
            hiddenListItem.classList.remove('hidden');
            hiddenListItem.querySelector('span').textContent = featureTitle;
            hiddenListItem.querySelector('a').href = '#' + key;
        }
    }
};
