package dev.u9g.minecraftdatagenerator.generators;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonPrimitive;
import dev.u9g.minecraftdatagenerator.util.DGU;
import net.minecraft.core.Holder;
import net.minecraft.core.Registry;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.Identifier;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.enchantment.Enchantment;

import java.util.List;
import java.util.Objects;
import java.util.stream.Collectors;

public class ItemsDataGenerator implements IDataGenerator {

    private static List<Item> calculateItemsToRepairWith(Registry<Item> itemRegistry, Item sourceItem) {
        ItemStack sourceItemStack = new ItemStack(sourceItem);
        return itemRegistry.stream()
                .filter(otherItem -> sourceItemStack.isValidRepairItem(new ItemStack(otherItem)))
                .collect(Collectors.toList());
    }

    public static JsonObject generateItem(Registry<Item> itemRegistry, Item item) {
        JsonObject itemDesc = new JsonObject();
        Identifier registryKey = itemRegistry.getKey(item);

        itemDesc.addProperty("id", itemRegistry.getId(item));
        itemDesc.addProperty("name", registryKey.getPath());

        itemDesc.addProperty("displayName", DGU.translateText(item.getDescriptionId()));
        itemDesc.addProperty("stackSize", item.getDefaultMaxStackSize());

        JsonArray enchantCategoriesArray = new JsonArray();
        DGU.getWorld().registryAccess().lookupOrThrow(Registries.ENCHANTMENT).stream()
                .map(Enchantment::getSupportedItems)
                .filter(applicableItems -> applicableItems.contains(itemRegistry.wrapAsHolder(item)))
                .map(EnchantmentsDataGenerator::getEnchantmentTargetName)
                .distinct()
                .forEach(enchantCategoriesArray::add);

        if (enchantCategoriesArray.size() > 0) {
            itemDesc.add("enchantCategories", enchantCategoriesArray);
        }

        if (item.components().has(DataComponents.MAX_DAMAGE)) {
            List<Item> repairWithItems = calculateItemsToRepairWith(itemRegistry, item);

            JsonArray fixedWithArray = new JsonArray();
            for (Item repairWithItem : repairWithItems) {
                Identifier repairWithName = itemRegistry.getKey(repairWithItem);
                fixedWithArray.add(repairWithName.getPath());
            }
            if (fixedWithArray.size() > 0) {
                itemDesc.add("repairWith", fixedWithArray);
            }

            int maxDurability = Objects.requireNonNull(item.components().get(DataComponents.MAX_DAMAGE));
            itemDesc.addProperty("maxDurability", maxDurability);
        }
        return itemDesc;
    }

    @Override
    public String getDataName() {
        return "items";
    }

    @Override
    public JsonArray generateDataJson() {
        JsonArray resultArray = new JsonArray();
        Registry<Item> itemRegistry = DGU.getWorld().registryAccess().lookupOrThrow(Registries.ITEM);
        itemRegistry.stream().forEach(item -> resultArray.add(generateItem(itemRegistry, item)));
        return resultArray;
    }
}
